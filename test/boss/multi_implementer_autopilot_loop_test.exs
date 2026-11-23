defmodule Boss.MultiImplementerAutopilotLoopTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Boss.{Deliveries, Projects, Repo, Tasks}
  alias Boss.Agents.{Detections, Roles}
  alias Boss.Deliveries.{Autopilot, AutopilotBatch, ImplementerBinding}
  alias Boss.Projects.{RoleBindings, TaskPrompt}
  alias Boss.Tasks.Entries

  setup %{conn: conn} do
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
        intake_mode: "documentation"
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
