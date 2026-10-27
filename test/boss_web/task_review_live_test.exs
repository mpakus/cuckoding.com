defmodule BossWeb.TaskReviewLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Boss.{LocalAccess, Projects, Repo, Runs}
  alias Boss.Runs.Manager
  alias BossWeb.ProjectLive

  @moduletag skip: :os.type() != {:unix, :darwin}

  setup %{conn: conn} do
    owner = self()
    original = :sys.get_state(Manager).review_worker
    assert :sys.get_state(Manager).active == %{}

    :sys.replace_state(Manager, fn state ->
      %{state | review_worker: fn run, _repo, manager -> fake_worker(owner, run, manager) end}
    end)

    on_exit(fn ->
      for {_, {_, pid}} <- :sys.get_state(Manager).active do
        ref = Process.monitor(pid)
        send(pid, :stop)
        assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
      end

      :sys.replace_state(Manager, &%{&1 | review_worker: original})
    end)

    project =
      Repo.insert!(%Projects.Project{
        name: "Review UI",
        root_path: "/review-ui",
        git_common_dir: "/review-ui/.git",
        specs_path: "/review-ui/specs",
        base_branch: "main"
      })

    saved = spec(project, "one")
    {parent, check} = checked_run(project, saved.task)
    {:ok, session} = LocalAccess.exchange(LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn, project: project, saved: saved, parent: parent, check: check}
  end

  test "only passed checks offer a separate explicit reviewer", ctx do
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    assert has_element?(view, "#start-review-#{ctx.check.id}", "Review with Codex")
    assert has_element?(view, "#review-help-#{ctx.check.id}", "read-only Codex session")
    assert has_element?(view, "#review-help-#{ctx.check.id}", "may incur charges")
    refute has_element?(view, "#start-review-#{ctx.parent.id}")

    {:ok, {:new, failed}} =
      Runs.admit_check(ctx.project.id, ctx.parent.id, Ecto.UUID.generate(), "test")

    {:ok, _} = Runs.update(failed.id, status: "failed", cleanup: "group_empty")
    Runs.broadcast(failed)
    settle(view)
    refute has_element?(view, "#start-review-#{failed.id}")
  end

  test "explicit review starts once, pins checked revision and renders escaped assessment", ctx do
    spec(ctx.project, "one", "# Newer source")
    {:ok, view, _} = live(ctx.conn, task_path(ctx) <> "?revision=2")
    settle(view)
    id = command(view, ctx.check.id)
    payload = input(ctx.check.id, id)
    render_click(view, "start_review", payload)
    assert_receive {:reviewing, worker, run}, 1_000
    settle(view)
    assert run.adapter == "review" && run.parent_run_id == ctx.check.id
    assert run.spec_revision_id == ctx.check.spec_revision_id
    assert run.candidate_commit == ctx.check.candidate_commit
    assert has_element?(view, "#start-codex[disabled]")
    assert has_element?(view, "#check-command-#{ctx.parent.id}[disabled]")
    render_click(view, "start_review", payload)
    refute_receive {:reviewing, _, _}, 50

    report = report("changes_requested")
    finish(worker, status: "finished", exit_kind: "exit", exit_code: 0, review_report: report)
    settle(view)
    assert has_element?(view, "#run-#{run.id}", "Model assessment: Changes requested")
    assert has_element?(view, "#run-#{run.id}", "<script>not executable</script>")
    refute has_element?(view, "#run-#{run.id} script")
    assert has_element?(view, "#run-#{run.id}", "Saved criterion")
    assert has_element?(view, "#run-#{run.id}", "Actionable correction")

    assert has_element?(
             view,
             "#run-#{run.id}",
             "A refined plan and raw test output were not provided"
           )

    refute command(view, ctx.check.id) == id
    assert Repo.get!(Boss.Tasks.Task, ctx.saved.task.id).state == "new"
  end

  test "approved report stays a model assessment, with the task still new", ctx do
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    view |> element("#start-review-#{ctx.check.id}") |> render_click()
    assert_receive {:reviewing, worker, run}, 1_000

    finish(worker,
      status: "finished",
      exit_kind: "exit",
      exit_code: 0,
      review_report: report("approved")
    )

    settle(view)
    assert has_element?(view, "#run-#{run.id}", "Model assessment: Approved")
    assert has_element?(view, "#run-#{run.id}", "Task approval and integration remain separate")
    assert has_element?(view, "#run-#{run.id}", "No issues reported")
    assert Repo.get!(Boss.Tasks.Task, ctx.saved.task.id).state == "new"
  end

  test "unknown admission locks its UUID and blocks other starts until receipt or retry", ctx do
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    id = command(view, ctx.check.id)
    payload = input(ctx.check.id, id)
    :sys.suspend(Manager)
    on_exit(fn -> :sys.resume(Manager) end)
    render_click(view, "start_review", payload)

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, :start_review, :kill)}
    end)

    settle(view)
    assert command(view, ctx.check.id) == id
    assert has_element?(view, "#start-review-#{ctx.check.id}", "Retry review")
    assert has_element?(view, "#review-start-pending")
    assert has_element?(view, "#start-codex[disabled]")
    assert has_element?(view, "#check-command-#{ctx.parent.id}[disabled]")
    render_click(view, "start_review", input(ctx.check.id, Ecto.UUID.generate()))
    render_click(view, "start_review", payload)
    :sys.resume(Manager)
    assert_receive {:reviewing, worker, run}, 1_000
    settle(view)
    assert run.command_id == id
    refute_receive {:reviewing, _, _}, 50
    assert length(Runs.list(ctx.project.id, ctx.saved.task.id)) == 3
    finish(worker)
  end

  test "stale check IDs cannot launch and review survives close and scoped Stop", ctx do
    other = spec(ctx.project, "other")
    {_, foreign} = checked_run(ctx.project, other.task)
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    id = command(view, ctx.check.id)
    render_click(view, "start_review", input(foreign.id, id))
    refute_receive {:reviewing, _, _}, 50
    render_click(view, "start_review", input(ctx.check.id, id))
    assert_receive {:reviewing, worker, run}, 1_000
    settle(view)
    render_patch(view, "/projects/#{ctx.project.id}")
    assert Process.alive?(worker)
    {:ok, reconnected, _} = live(ctx.conn, task_path(ctx))
    settle(reconnected)
    assert has_element?(reconnected, "#run-#{run.id}", "Verifying review snapshot")
    reconnected |> element("#stop-run-#{run.id}") |> render_click()
    assert_receive {:fixture_finished, finished_id}, 1_000
    assert finished_id == run.id
    settle(reconnected)
    assert has_element?(reconnected, "#run-#{run.id}", "Cancelled — workspace retained")
    refute has_element?(reconnected, "#run-#{run.id}", "Model assessment")
  end

  test "persisted receipt wins over late unknown admission and unlocks all actions", ctx do
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    id = command(view, ctx.check.id)
    render_click(view, "start_review", input(ctx.check.id, id))
    assert_receive {:reviewing, worker, _}, 1_000
    finish(worker)
    settle(view)
    renewed = command(view, ctx.check.id)
    refute renewed == id

    for result <- [
          {:ok, {ctx.saved.task.id, ctx.check.id, id, {:error, :storage_error}}},
          {:exit, :killed}
        ] do
      :sys.replace_state(view.pid, fn state ->
        socket = Phoenix.Component.assign(state.socket, run_starting: {ctx.saved.task.id, id})
        {:noreply, socket} = ProjectLive.handle_async(:start_review, result, socket)
        %{state | socket: socket}
      end)

      settle(view)
      assert command(view, ctx.check.id) == renewed
      refute has_element?(view, "#run-error")
      refute has_element?(view, "#review-start-pending")
      refute has_element?(view, "#start-codex[disabled]")
    end
  end

  test "known busy leaves request retryable and does not launch a reviewer", ctx do
    other = spec(ctx.project, "other")
    {:ok, {:new, busy}} = Runs.admit(ctx.project.id, other.task.id, Ecto.UUID.generate())
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    id = command(view, ctx.check.id)
    render_click(view, "start_review", input(ctx.check.id, id))
    settle(view)
    assert has_element?(view, "#run-error", "Another run is active")
    assert has_element?(view, "#start-review-#{ctx.check.id}", "Review with Codex")
    refute has_element?(view, "#review-start-pending")
    assert command(view, ctx.check.id) == id
    refute_receive {:reviewing, _, _}, 50
    {:ok, _} = Runs.update(busy.id, status: "failed", cleanup: "group_empty")
  end

  test "a late reply from an earlier review cannot clear a newer start", ctx do
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    old = command(view, ctx.check.id)
    render_click(view, "start_review", input(ctx.check.id, old))
    assert_receive {:reviewing, worker, _}, 1_000
    finish(worker)
    settle(view)
    current = command(view, ctx.check.id)

    :sys.replace_state(view.pid, fn state ->
      request = %{id: current, locked: true}

      socket =
        Phoenix.Component.assign(state.socket,
          run_starting: {ctx.saved.task.id, current},
          review_requests: %{ctx.check.id => request}
        )

      {:noreply, socket} =
        ProjectLive.handle_async(
          :start_review,
          {:ok, {ctx.saved.task.id, ctx.check.id, old, {:error, :storage_error}}},
          socket
        )

      %{state | socket: socket}
    end)

    assert :sys.get_state(view.pid).socket.assigns.run_starting == {ctx.saved.task.id, current}
  end

  test "review history keeps both source levels exactly once", ctx do
    for _ <- 1..11 do
      {:ok, {:new, run}} = Runs.admit_review(ctx.project.id, ctx.check.id, Ecto.UUID.generate())
      {:ok, _} = Runs.update(run.id, status: "failed", cleanup: "group_empty")
    end

    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    assert has_element?(view, "#start-review-#{ctx.check.id}")
    assert has_element?(view, "#check-form-#{ctx.parent.id}")
    html = render(view) |> LazyHTML.from_document()
    assert Enum.count(LazyHTML.query(html, "#run-attempts > li")) == 12
    assert Enum.count(LazyHTML.query(html, "#run-#{ctx.check.id}")) == 1
    assert Enum.count(LazyHTML.query(html, "#run-#{ctx.parent.id}")) == 1
  end

  defp checked_run(project, task) do
    {:ok, {:new, parent}} = Runs.admit(project.id, task.id, Ecto.UUID.generate())

    workspace = %{
      "project_id" => to_string(project.id),
      "run_id" => parent.id,
      "repo_path" => project.root_path,
      "git_common_dir" => project.git_common_dir,
      "base_branch" => "main",
      "base_commit" => String.duplicate("a", 40),
      "path" => "/retained/#{parent.id}",
      "branch" => "codex/boss-run-#{parent.id}"
    }

    {:ok, parent} =
      Runs.update(parent.id, status: "finished", cleanup: "group_empty", workspace: workspace)

    {:ok, {:new, check}} =
      Runs.admit_check(project.id, parent.id, Ecto.UUID.generate(), "mix test")

    {:ok, check} =
      Runs.update(check.id,
        status: "finished",
        cleanup: "group_empty",
        candidate_commit: String.duplicate("b", 40),
        exit_kind: "exit",
        exit_code: 0,
        workspace: %{
          "run_workspace" => workspace,
          "check_id" => check.id,
          "path" => "/checks/#{check.id}",
          "ref" => "refs/boss/checks/#{check.id}"
        }
      )

    {parent, check}
  end

  defp report(verdict) do
    %{
      "verdict" => verdict,
      "summary" => "<script>not executable</script>",
      "acceptance" => [
        %{
          "criterion" => "Saved criterion",
          "status" => if(verdict == "approved", do: "passed", else: "failed"),
          "evidence" => "Inspected file:10"
        }
      ],
      "issues" =>
        if(verdict == "approved",
          do: [],
          else: [%{"criterion" => "Saved criterion", "message" => "Actionable correction"}]
        )
    }
  end

  defp spec(project, name, source \\ "# One\nSaved criterion") do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: "#{name}.md",
        title: name,
        original_text: source
      })

    saved
  end

  defp fake_worker(owner, run, manager) do
    send(owner, {:reviewing, self(), run})

    attrs =
      receive do
        {:finish, attrs} -> attrs
        :stop -> [status: "cancelled"]
      after
        10_000 -> [status: "cancelled"]
      end

    result =
      Runs.update(
        run.id,
        Keyword.merge(
          [status: "failed", cleanup: "group_empty", finished_at: DateTime.utc_now()],
          attrs
        )
      )

    send(manager, {:run_finished, run.id, self(), result})
    send(owner, {:fixture_finished, run.id})
  end

  defp finish(worker, attrs \\ []) do
    send(worker, {:finish, attrs})
    assert_receive {:fixture_finished, _}, 1_000
    :sys.get_state(Manager)
  end

  defp input(parent, id), do: %{"parent-id" => parent, "command-id" => id}
  defp task_path(ctx), do: "/projects/#{ctx.project.id}/tasks/#{ctx.saved.task.id}"

  defp command(view, parent) do
    view
    |> element("#start-review-#{parent}")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("phx-value-command-id")
    |> hd()
  end

  defp settle(view) do
    render(view)
    render_async(view)
    render_async(view)
    render_async(view)
  end
end
