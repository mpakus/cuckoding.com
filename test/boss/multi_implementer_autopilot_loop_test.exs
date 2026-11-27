defmodule Boss.MultiImplementerAutopilotLoopTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Boss.{Deliveries, Projects, Repo, Tasks}
  alias Boss.Agents.{Detections, Roles}
  alias Boss.Deliveries.{Autopilot, AutopilotBatch, ImplementerBinding}
  alias Boss.Projects.{RoleBindings, TaskPrompt}
  alias Boss.Tasks.Entries

  setup %{conn: conn} = context do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-multi-loop-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    docs_dir = Path.join(root, "docs")
    File.mkdir!(docs_dir)

    File.write!(
      Path.join(docs_dir, "TASKS-LIST.md"),
      "# Delivery Checklist\n\n## Phase 0 — Bootstrap\n- Setup app\n\n## Phase 1 — Auth\n- Add login\n"
    )

    {_, 0} = System.cmd("git", ["-C", root, "init", "-b", "main"])
    {_, 0} = System.cmd("git", ["-C", root, "add", "."])

    {_, 0} =
      System.cmd("git", [
        "-C",
        root,
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "-m",
        "init docs"
      ])

    {_, 0} = System.cmd("git", ["-C", root, "checkout", "-b", "observer"])

    {:ok, project} =
      Projects.create_project(%{
        name: "LoopProj",
        root_path: root,
        specs_path: "docs",
        base_branch: "main",
        intake_mode: if(context[:files], do: "specs", else: "documentation")
      })

    seed_authorized_agents()
    conn = %{conn | host: "127.0.0.1", port: 4002}

    %{conn: conn, project: project, root: root, docs_dir: docs_dir}
  end

  test "requeue_interrupted_tasks unblocks root prerequisite so Start Autopilot launches it", c do
    {:ok, %{task: t1}} =
      Projects.record_spec(c.project.id, %{
        explicit_id: "m0-bootstrap",
        relative_path: "autopilot/m0-bootstrap.md",
        title: "Bootstrap foundation",
        original_text: "---\ndepends_on: []\n---\n# Bootstrap foundation\n\nSetup app."
      })

    {:ok, %{task: t2}} =
      Projects.record_spec(c.project.id, %{
        explicit_id: "m1-auth",
        relative_path: "autopilot/m1-auth.md",
        title: "Accounts auth",
        original_text:
          "---\ndepends_on: [\"m0-bootstrap\"]\n---\n# Accounts auth\n\nDepends on bootstrap."
      })

    {:ok, {:new, d1}} =
      Deliveries.admit(c.project.id, t1.id, Ecto.UUID.generate(), "")

    {:ok, _interrupted} = Deliveries.interrupt(d1.id)
    {:ok, _} = Deliveries.release_unknown_cleanups()

    # Reproduce exact /projects/1 deadlock: delivery is blocked+group_empty while task is interrupted
    assert Repo.get!(Deliveries.Delivery, d1.id).status == "blocked"
    assert Tasks.get_task!(t1.id).state == "interrupted"
    assert {:ok, [only_t2]} = Autopilot.selection(c.project.id)
    assert only_t2 == t2.id

    # Recovering interrupted tasks transitions t1 cleanly to blocked and makes both eligible
    assert {:ok, [_]} = Deliveries.requeue_interrupted_tasks(c.project.id)
    assert Tasks.get_task!(t1.id).state == "blocked"
    assert {:ok, selected_ids} = Autopilot.selection(c.project.id)
    assert Enum.sort(selected_ids) == Enum.sort([t1.id, t2.id])
  end

  test "Multi-Implementer Pool dispatches ready tasks in parallel across distinct Implementers and re-queues Reviewer spec rework back to Backlog",
       c do
    {:ok, _} = Roles.add_binding("implementer", "cursor", %{"model_id" => "gemini-4-carbon"})

    {:ok, _} =
      Roles.add_binding("implementer", "opencode", %{
        "model_id" => "opencode/minimax-m2.5-free"
      })

    {:ok, _} = Roles.add_binding("reviewer", "cursor", %{"model_id" => "gemini-4-carbon"})
    {:ok, _} = Roles.add_binding("analytic", "claude", %{"model_id" => "claude-opus-4-6"})

    assert {:ok, _} = RoleBindings.enable_all_implementers(c.project.id)
    assert RoleBindings.implementer_pool_size(c.project.id) >= 2

    {:ok, %{task: t1}} =
      Projects.record_spec(c.project.id, %{
        explicit_id: "task-alpha",
        relative_path: "autopilot/task-alpha.md",
        title: "Alpha service",
        original_text: "---\ndepends_on: []\n---\n# Alpha service\n\nBuild alpha."
      })

    {:ok, %{task: t2}} =
      Projects.record_spec(c.project.id, %{
        explicit_id: "task-beta",
        relative_path: "autopilot/task-beta.md",
        title: "Beta service",
        original_text: "---\ndepends_on: []\n---\n# Beta service\n\nBuild beta."
      })

    assert {:ok, batch} =
             Autopilot.admit(
               c.project.id,
               Ecto.UUID.generate(),
               [t1.id, t2.id],
               "",
               "cursor",
               false,
               nil,
               parallel: true,
               spec_loop: true
             )

    # First advance launches task 1 on Implementer #1
    assert {:ok, {:launch, :deliver, del1, batch_id}} = Autopilot.advance()
    assert batch_id == batch.id

    # Second advance launches task 2 IN PARALLEL while del1 is still planning!
    assert {:ok, {:launch, :deliver, del2, ^batch_id}} = Autopilot.advance()
    assert del1.id != del2.id

    b1 = Repo.get!(ImplementerBinding, del1.id)
    b2 = Repo.get!(ImplementerBinding, del2.id)
    assert b1.binding_tag != b2.binding_tag

    # Board live meta reflects both active parallel workflows
    meta = Projects.board_live_meta(c.project.id)
    assert meta[t1.id].implementer_tag == b1.binding_tag
    assert meta[t2.id].implementer_tag == b2.binding_tag

    # Simulate del1 & del2 finishing blocked with Reviewer feedback -> SpecRework refines specs,
    # moves tasks back to Backlog ("new"), and Autopilot starts Loop Pass 2 automatically!
    {:ok, _} =
      Deliveries.complete(
        del1.id,
        "blocked",
        "Reviewer requested explicit rate-limit header acceptance."
      )

    {:ok, _} =
      Deliveries.complete(
        del2.id,
        "blocked",
        "Reviewer requested idempotency key validation."
      )

    assert {:ok, {:restarted_loop, pass2}} = Autopilot.advance()
    assert pass2.id != batch.id
    assert pass2.status == "running"
    assert Enum.sort(pass2.task_ids) == Enum.sort([t1.id, t2.id])

    # Both tasks were refined with new spec revisions, logged in task_entries, and reset to "new" (Backlog)!
    reworked_t1 = Tasks.get_task!(t1.id)
    assert reworked_t1.state == "new"

    entries_t1 = Entries.list_for_task(c.project.id, t1.id)
    assert Enum.any?(entries_t1, &(&1.kind == "spec_update" and &1.author_role == "reviewer"))

    loop_cfg = Autopilot.loop_info(pass2.id)
    assert loop_cfg.loop_pass == 2
    assert loop_cfg.parent_autopilot_id == batch.id
    assert Repo.get!(AutopilotBatch, batch.id).status == "blocked"
  end

  @tag files: true
  test "file-backed rework keeps original bytes and the watcher follows real edits", c do
    {file, text, task, delivery} = blocked_file(c)
    assert rework(c.project, delivery) == [task.id]
    assert File.read!(file) == text
    [original, refined] = Projects.list_spec_revisions(task.spec_id)
    assert String.starts_with?(refined.original_text, original.original_text)
    assert refined.original_text =~ "Reviewer Spec Refinement"
    assert Tasks.get_task!(task.id).spec_revision_id == refined.id
    assert {:ok, %{revised: 0}} = Projects.SpecImporter.sync(c.project.id)

    File.write!(Path.join(c.docs_dir, "unrelated.md"), "# Another task")
    assert {:ok, %{created: 1, revised: 0}} = Projects.SpecImporter.sync(c.project.id)
    assert [^original, ^refined] = Projects.list_spec_revisions(task.spec_id)

    File.write!(file, refined.original_text)
    assert {:ok, %{revised: 1}} = Projects.SpecImporter.sync(c.project.id)
    File.write!(file, text)
    assert {:ok, %{revised: 1}} = Projects.SpecImporter.sync(c.project.id)
    File.rename!(file, Path.join(c.docs_dir, "renamed.md"))
    assert {:ok, %{revised: 1}} = Projects.SpecImporter.sync(c.project.id)

    assert [^original, ^refined, observed, reverted, moved] =
             Projects.list_spec_revisions(task.spec_id)

    assert observed.original_text == refined.original_text
    assert reverted.original_text == moved.original_text and moved.original_text == text
    assert moved.relative_path == "renamed.md"
    pinned = Tasks.get_task!(task.id)
    assert pinned.spec_revision_id == refined.id

    assert {:ok, _} =
             Tasks.transition(task.id, %{
               action: "adopt_revision",
               project_id: c.project.id,
               spec_revision_id: moved.id,
               expected_version: pinned.state_version,
               command_id: Ecto.UUID.generate()
             })

    assert Tasks.get_task!(task.id).spec_revision_id == moved.id
  end

  @tag files: true
  test "a newer work file or imported revision survives stale review feedback", c do
    {path, old, task, delivery} = blocked_file(c)
    newer = old <> "Owner changed the requirement."
    File.write!(path, newer)
    assert rework(c.project, delivery) == []
    assert File.read!(path) == newer
    assert [_] = Projects.list_spec_revisions(task.spec_id)
    assert {:ok, %{revised: 1}} = Projects.SpecImporter.sync(c.project.id)
    File.write!(path, old)
    assert rework(c.project, delivery) == []
    assert File.read!(path) == old
    assert [_, latest] = Projects.list_spec_revisions(task.spec_id)
    assert latest.original_text == newer
    assert Tasks.get_task!(task.id).state == "blocked"
    refute Enum.any?(Entries.list_for_task(c.project.id, task.id), &(&1.stage == "spec_rework"))
  end

  @tag files: true
  test "failed rework receipt rolls back adoption, derived source and revision", c do
    {file, text, task, delivery} = blocked_file(c)
    Repo.query!("ALTER TABLE task_entries RENAME TO unavailable_task_entries")
    assert {:error, :spec_rework_failed} = rework(c.project, delivery)
    assert File.read!(file) == text
    assert [original] = Projects.list_spec_revisions(task.spec_id)
    assert original.id == task.spec_revision_id
    assert Tasks.get_task!(task.id).state == "blocked"
    assert Repo.query!("SELECT COUNT(*) FROM spec_rework_revisions").rows == [[0]]
  end

  defp blocked_file(c) do
    file = Path.join(c.docs_dir, "customer.md")

    source =
      "---\r\nid: customer\r\ntitle: Owner title\r\npriority: high # preserve\r\n---\r\n# Contract\r\n\r\nExact content  \r\n"

    File.write!(file, source)
    assert {:ok, _} = Projects.SpecImporter.sync(c.project.id)

    entry =
      Enum.find(Projects.list_spec_entries(c.project.id), &(&1.relative_path == "customer.md"))

    task = Tasks.get_task!(entry.task_id)
    {:ok, {:new, d}} = Deliveries.admit(c.project.id, task.id, Ecto.UUID.generate(), "")
    {:ok, blocked} = Deliveries.complete(d.id, "blocked", "Add a rate-limit header.")
    {file, source, task, blocked}
  end

  defp rework(project, delivery),
    do:
      Boss.Deliveries.SpecRework.refine_settled_deliveries(
        project.id,
        [{nil, nil, delivery, nil}],
        1
      )

  for {loop?, outcome} <- [{true, :restarted_loop}, {false, :changed}] do
    @loop loop?
    @outcome outcome
    test "a blocked prerequisite with a queued dependent honors loop=#{loop?}", c do
      {prerequisite, dependent} = dependency_pair(c.project)
      ids = [prerequisite.id, dependent.id]
      check = ~S(true "" "argument with spaces" final)

      assert {:ok, batch} =
               Autopilot.admit(
                 c.project.id,
                 Ecto.UUID.generate(),
                 ids,
                 check,
                 "cursor",
                 false,
                 nil,
                 parallel: true,
                 spec_loop: @loop
               )

      assert {:ok, {:launch, :deliver, first, _}} = Autopilot.advance()
      assert first.task_id == prerequisite.id
      assert first.check_config["argv"] == ["true", "", "argument with spaces", "final"]
      assert {:ok, :waiting} = Autopilot.advance()

      assert {:ok, _} =
               Deliveries.complete(
                 first.id,
                 "blocked",
                 "Reviewer requested a missing runtime assertion."
               )

      assert {:ok, {@outcome, result}} = Autopilot.advance()

      original = Repo.get!(Deliveries.Request, List.last(batch.items).request_id)
      assert original.status == "cancelled"
      assert original.delivery_id == nil

      if @loop do
        assert result.task_ids == ids
        assert result.check_config == batch.check_config
        assert result.config_hash == batch.config_hash

        for item <- result.items do
          request = Repo.get!(Deliveries.Request, item.request_id)
          assert request.check_config == first.check_config
          assert request.config_hash == first.config_hash
        end

        assert result.reviewer == batch.reviewer
        assert Autopilot.loop_info(result.id).parent_autopilot_id == batch.id
        assert List.last(result.items).request_id != original.id

        assert {:error, {:dependencies_blocked, _}} =
                 Tasks.Dependencies.check(c.project.id, dependent.id)

        assert {:ok, {:launch, :deliver, second, next_batch_id}} = Autopilot.advance()
        assert {second.task_id, next_batch_id} == {prerequisite.id, result.id}

        assert {:ok, _} =
                 Deliveries.complete(
                   second.id,
                   "blocked",
                   "Reviewer still needs the runtime assertion."
                 )

        assert {:ok, {:changed, exhausted}} = Autopilot.advance()
        assert exhausted.id == result.id and exhausted.status == "blocked"
        assert exhausted.reason =~ "No remaining task is ready"
        assert Repo.aggregate(AutopilotBatch, :count) == 2
      else
        assert result.id == batch.id and result.status == "blocked"
        assert result.reason =~ "No remaining task is ready"
        assert Repo.aggregate(AutopilotBatch, :count) == 1
      end
    end
  end

  test "a new arrival cannot enter an already authorized recovery pass", c do
    {prerequisite, dependent} = dependency_pair(c.project)

    assert {:ok, batch} =
             Autopilot.admit(
               c.project.id,
               Ecto.UUID.generate(),
               [prerequisite.id, dependent.id],
               "true",
               "cursor",
               false,
               nil,
               spec_loop: true
             )

    assert {:ok, {:launch, :deliver, first, _}} = Autopilot.advance()

    assert {:ok, %{task: later}} =
             Projects.record_spec(c.project.id, %{
               relative_path: "autopilot/later.md",
               title: "Later",
               original_text: "# Later"
             })

    assert {:ok, _} = Deliveries.complete(first.id, "blocked", "Reviewer requested an assertion.")
    assert {:ok, {:changed, halted}} = Autopilot.advance()
    assert halted.id == batch.id and halted.status == "blocked"
    assert halted.reason =~ "differs from the authorized loop tasks"
    assert Repo.aggregate(AutopilotBatch, :count) == 1
    assert Deliveries.Queue.list(c.project.id, later.id) == []
  end

  defp dependency_pair(project) do
    records =
      for {id, dependencies} <- [{"setup", "[]"}, {"acceptance", "[setup]"}] do
        assert {:ok, %{task: task}} =
                 Projects.record_spec(project.id, %{
                   explicit_id: id,
                   relative_path: "autopilot/#{id}.md",
                   title: id,
                   original_text: "---\ndepends_on: #{dependencies}\n---\n# #{id}\n"
                 })

        task
      end

    List.to_tuple(records)
  end

  test "TaskPrompt includes docs/ directory index and UI offers Multi-Implementer Pool, docs presets & animated board",
       c do
    {:ok, _} = Roles.add_binding("implementer", "cursor", %{"model_id" => "gemini-4-carbon"})

    {:ok, _} =
      Roles.add_binding("implementer", "opencode", %{
        "model_id" => "opencode/minimax-m2.5-free"
      })

    prompt = TaskPrompt.build_prompt(c.project, [], "Break down docs/", "", "cursor", "analytic")
    assert prompt =~ "TASKS-LIST.md"
    assert prompt =~ "Delivery Checklist"

    {:ok, view, _html} = live(c.conn, ~p"/projects/#{c.project.id}")
    render_async(view, 2_000)

    assert has_element?(view, "#task-board[phx-hook=TaskBoardMotion]")
    refute has_element?(view, "#project-roles-dialog")
    refute has_element?(view, "#task-prompt-dialog")

    view |> element("#open-project-roles") |> render_click()
    assert has_element?(view, "#project-roles-dialog")
    assert has_element?(view, "#project-implementer-pool")
    assert has_element?(view, "#enable-all-implementers")

    view |> element("#enable-all-implementers") |> render_click()
    render_async(view, 2_000)
    assert has_element?(view, "#project-implementer-pool-badge", "2 parallel")
    view |> element("#close-project-roles") |> render_click()
    refute has_element?(view, "#project-roles-dialog")
    assert has_element?(view, "#project-roles-trigger-pool", "2 parallel")

    view |> element("#open-task-prompt") |> render_click()
    assert has_element?(view, "#task-prompt-dialog")
    assert has_element?(view, "#preset-analytic-parse-docs")
    assert has_element?(view, "#preset-reviewer-refine-docs")
    view |> element("#preset-analytic-parse-docs") |> render_click()
    assert render(view) =~ "Analyze the project"
  end

  test "stop_for_autopilot recovers an orphaned or wedged active delivery and re-includes its task",
       c do
    {:ok, %{task: t1}} =
      Projects.record_spec(c.project.id, %{
        explicit_id: "m0-bootstrap",
        relative_path: "autopilot/m0-bootstrap.md",
        title: "Phoenix foundation",
        original_text: "---\ndepends_on: []\n---\n# Phoenix foundation\n\nSetup app."
      })

    {:ok, %{task: t2}} =
      Projects.record_spec(c.project.id, %{
        explicit_id: "m1-auth",
        relative_path: "autopilot/m1-auth.md",
        title: "Accounts auth",
        original_text:
          "---\ndepends_on: [\"m0-bootstrap\"]\n---\n# Accounts auth\n\nDepends on bootstrap."
      })

    {:ok, {:new, d1}} =
      Deliveries.admit(c.project.id, t1.id, Ecto.UUID.generate(), "")

    assert %{
             kind: :project_delivery,
             delivery_id: blocker_id,
             task_id: blocker_task_id,
             task_title: "Phoenix foundation"
           } = Deliveries.autopilot_blocker(c.project.id)

    assert blocker_id == d1.id
    assert blocker_task_id == t1.id

    assert {:ok, settled} =
             Deliveries.stop_for_autopilot(c.project.id, d1.id, grace_ms: 50)

    assert settled.status == "blocked"
    assert settled.cleanup == "group_empty"
    assert Tasks.get_task!(t1.id).state == "blocked"
    assert is_nil(Deliveries.autopilot_blocker(c.project.id))

    assert {:ok, selected_ids} = Autopilot.selection(c.project.id)
    assert Enum.sort(selected_ids) == Enum.sort([t1.id, t2.id])
  end

  defp seed_authorized_agents do
    for {id, name, models} <- [
          {:cursor, "Cursor Agent",
           [
             %{
               "id" => "gemini-4-carbon",
               "name" => "Gemini 4 Carbon",
               "billing" => "subscription_or_api",
               "pricing" => %{"input" => 1.25, "output" => 10.0, "unit" => "1M tokens"}
             }
           ]},
          {:opencode, "OpenCode",
           [
             %{
               "id" => "opencode/minimax-m2.5-free",
               "name" => "MiniMax M2.5 Free",
               "billing" => "free",
               "pricing" => %{"input" => 0.0, "output" => 0.0, "unit" => "1M tokens"}
             }
           ]},
          {:claude, "Claude Code",
           [
             %{
               "id" => "claude-opus-4-6",
               "name" => "Claude Opus 4.6",
               "billing" => "subscription_or_api",
               "pricing" => %{"input" => 5.0, "output" => 25.0, "unit" => "1M tokens"}
             }
           ]}
        ] do
      Detections.save_agent(%{
        id: id,
        name: name,
        path: "/tools/#{id}",
        version: "1.2.3",
        probe_status: :ok,
        auth_status: :configured,
        capabilities: %{},
        errors: [],
        models: models
      })
    end
  end
end
