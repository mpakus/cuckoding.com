defmodule BossWeb.TaskChecksLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Boss.{LocalAccess, Projects, Repo, Runs}
  alias Boss.Runs.Manager
  alias BossWeb.ProjectLive

  @moduletag skip: :os.type() != {:unix, :darwin}

  setup %{conn: conn} do
    owner = self()
    original = :sys.get_state(Manager).check_worker
    assert :sys.get_state(Manager).active == %{}

    :sys.replace_state(Manager, fn state ->
      %{state | check_worker: fn run, _repo, manager -> fake_worker(owner, run, manager) end}
    end)

    on_exit(fn ->
      for {_, {_, pid}} <- :sys.get_state(Manager).active do
        ref = Process.monitor(pid)
        send(pid, :stop)
        assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
      end

      :sys.replace_state(Manager, &%{&1 | check_worker: original})
    end)

    project =
      Repo.insert!(%Projects.Project{
        name: "Check UI",
        root_path: "/checks-ui",
        git_common_dir: "/checks-ui/.git",
        specs_path: "/checks-ui/specs",
        base_branch: "main"
      })

    saved = spec(project, "one")
    parent = parent_run(project, saved.task)
    {:ok, session} = LocalAccess.exchange(LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn, project: project, saved: saved, parent: parent}
  end

  test "only finished Codex results offer explicit checks without source-derived commands", ctx do
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    assert has_element?(view, "#check-form-#{ctx.parent.id}")
    assert has_element?(view, "#check-command-#{ctx.parent.id}[value='']")
    assert has_element?(view, "#check-form-#{ctx.parent.id}", "using your account's access")
    refute has_element?(view, "#check-command-#{ctx.parent.id}[value*='UNTRUSTED']")

    other = spec(ctx.project, "other")
    {:ok, {:new, incomplete}} = Runs.admit(ctx.project.id, other.task.id, Ecto.UUID.generate())
    {:ok, _} = Runs.update(incomplete.id, status: "failed", cleanup: "group_empty")
    render_patch(view, "/projects/#{ctx.project.id}/tasks/#{other.task.id}")
    settle(view)
    refute has_element?(view, "form[id^='check-form-']")
  end

  test "explicit quoted argv starts once, preserves source pin, and displays commit-bound success",
       ctx do
    spec(ctx.project, "one", "# Newer source")
    {:ok, view, _} = live(ctx.conn, task_path(ctx) <> "?revision=2")
    settle(view)
    id = command(view, ctx.parent.id)
    payload = input(ctx.parent.id, id, ~s(printf "%s" "two words"))
    view |> form("#check-form-#{ctx.parent.id}", payload) |> render_submit()
    assert_receive {:checking, worker, run}, 1_000
    settle(view)
    assert run.adapter == "check"
    assert run.parent_run_id == ctx.parent.id
    assert run.spec_revision_id == ctx.parent.spec_revision_id
    assert run.check_config["argv"] == ["printf", "%s", "two words"]
    assert has_element?(view, "#start-codex[disabled]")
    render_submit(view, "start_check", payload)
    refute_receive {:checking, _, _}, 50
    assert length(Runs.list(ctx.project.id, ctx.saved.task.id)) == 2

    finish(worker,
      status: "finished",
      candidate_commit: String.duplicate("b", 40),
      exit_kind: "exit",
      exit_code: 0
    )

    settle(view)
    assert has_element?(view, "#run-#{run.id}", "Checks passed — review required")
    assert has_element?(view, "#run-#{run.id}", String.duplicate("b", 40))
    assert has_element?(view, "#run-#{run.id}", "Later workspace edits have not been checked")
    assert has_element?(view, "#run-#{run.id}", "Exit code: 0")
    refute has_element?(view, "#run-#{run.id}", "Codex finished")
    refute command(view, ctx.parent.id) == id
    assert Repo.get!(Boss.Tasks.Task, ctx.saved.task.id).state == "new"
  end

  test "unknown admission locks exact input and UUID; changed commands cannot silently retry",
       ctx do
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    id = command(view, ctx.parent.id)
    payload = input(ctx.parent.id, id, "mix test")
    :sys.suspend(Manager)
    on_exit(fn -> :sys.resume(Manager) end)
    render_submit(view, "start_check", payload)

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, :start_check, :kill)}
    end)

    settle(view)
    assert command(view, ctx.parent.id) == id
    assert has_element?(view, "#check-command-#{ctx.parent.id}[readonly][value='mix test']")
    assert has_element?(view, "#run-error", "could not be confirmed")
    assert has_element?(view, "#start-codex[disabled]")
    render_change(view, "edit_check", input(ctx.parent.id, id, "mix compile"))
    render_submit(view, "start_check", input(ctx.parent.id, id, "mix compile"))
    assert has_element?(view, "#check-command-#{ctx.parent.id}[value='mix test']")
    render_submit(view, "start_check", payload)
    :sys.resume(Manager)
    assert_receive {:checking, worker, run}, 1_000
    settle(view)
    assert run.command_id == id
    assert run.check_config["argv"] == ["mix", "test"]
    assert length(Runs.list(ctx.project.id, ctx.saved.task.id)) == 2
    refute_receive {:checking, _, _}, 50
    finish(worker)
  end

  test "stale source IDs are rejected and running checks survive close, reconnect and scoped Stop",
       ctx do
    other = spec(ctx.project, "other")
    foreign_parent = parent_run(ctx.project, other.task)
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    id = command(view, ctx.parent.id)
    render_submit(view, "start_check", input(foreign_parent.id, id, "mix test"))
    refute_receive {:checking, _, _}, 50
    render_submit(view, "start_check", input(ctx.parent.id, id, "mix test"))
    assert_receive {:checking, worker, run}, 1_000
    settle(view)
    render_patch(view, "/projects/#{ctx.project.id}")
    assert Process.alive?(worker)
    {:ok, reconnected, _} = live(ctx.conn, task_path(ctx))
    settle(reconnected)
    assert has_element?(reconnected, "#run-#{run.id}", "Capturing check snapshot")
    reconnected |> element("#stop-run-#{run.id}") |> render_click()
    assert_receive {:fixture_finished, finished_id}, 1_000
    assert finished_id == run.id
    settle(reconnected)
    assert has_element?(reconnected, "#run-#{run.id}", "Cancelled — workspace retained")
    refute has_element?(reconnected, "#run-#{run.id}", "Checks passed")
  end

  test "a persisted terminal receipt suppresses a later unknown admission result", ctx do
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    id = command(view, ctx.parent.id)
    render_submit(view, "start_check", input(ctx.parent.id, id, "mix test"))
    assert_receive {:checking, worker, _}, 1_000
    finish(worker)
    settle(view)
    renewed = command(view, ctx.parent.id)
    refute renewed == id

    for result <- [
          {:ok, {ctx.saved.task.id, ctx.parent.id, id, {:error, :storage_error}}},
          {:exit, :killed}
        ] do
      :sys.replace_state(view.pid, fn state ->
        socket = Phoenix.Component.assign(state.socket, run_starting: {ctx.saved.task.id, id})
        {:noreply, socket} = ProjectLive.handle_async(:start_check, result, socket)
        %{state | socket: socket}
      end)

      settle(view)
      assert command(view, ctx.parent.id) == renewed
      refute has_element?(view, "#run-error")
      refute has_element?(view, "#check-start-pending")
      refute has_element?(view, "#check-command-#{ctx.parent.id}[readonly]")
    end
  end

  test "known invalid input remains editable and never starts a worker", ctx do
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    id = command(view, ctx.parent.id)
    render_submit(view, "start_check", input(ctx.parent.id, id, "   "))
    settle(view)
    assert has_element?(view, "#run-error", "Enter one command")
    refute has_element?(view, "#check-command-#{ctx.parent.id}[readonly]")
    assert command(view, ctx.parent.id) == id
    render_submit(view, "start_check", input(ctx.parent.id, id, String.duplicate("é", 2049)))
    assert has_element?(view, "#run-error", "4096 bytes")
    refute has_element?(view, "#check-command-#{ctx.parent.id}[readonly]")
    refute_receive {:checking, _, _}, 50
  end

  test "ten check attempts keep their source action and nonzero exits never look passed", ctx do
    for _ <- 1..11 do
      {:ok, {:new, run}} =
        Runs.admit_check(ctx.project.id, ctx.parent.id, Ecto.UUID.generate(), "mix test")

      {:ok, _} =
        Runs.update(run.id,
          status: "failed",
          cleanup: "group_empty",
          exit_kind: "exit",
          exit_code: 1
        )
    end

    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    assert has_element?(view, "#check-form-#{ctx.parent.id}")
    assert has_element?(view, "#task-runs", "Latest 10 attempts and source runs")
    assert has_element?(view, "#run-attempts", "Checks failed")
    assert has_element?(view, "#run-attempts", "Exit code: 1")
    refute has_element?(view, "#run-attempts", "Checks passed")

    assert render(view)
           |> LazyHTML.from_document()
           |> LazyHTML.query("#run-attempts > li")
           |> Enum.count() == 11
  end

  defp parent_run(project, task) do
    {:ok, {:new, run}} = Runs.admit(project.id, task.id, Ecto.UUID.generate())

    workspace = %{
      "project_id" => to_string(project.id),
      "run_id" => run.id,
      "repo_path" => project.root_path,
      "git_common_dir" => project.git_common_dir,
      "base_branch" => "main",
      "base_commit" => String.duplicate("a", 40),
      "path" => "/retained/#{run.id}",
      "branch" => "codex/boss-run-#{run.id}"
    }

    {:ok, run} =
      Runs.update(run.id, status: "finished", cleanup: "group_empty", workspace: workspace)

    run
  end

  defp spec(project, name, source \\ "# One\nDo not run UNTRUSTED_MODEL_COMMAND automatically.") do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: "#{name}.md",
        title: name,
        original_text: source
      })

    saved
  end

  defp fake_worker(owner, run, manager) do
    send(owner, {:checking, self(), run})

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

  defp input(parent, id, text),
    do: %{"parent_id" => parent, "command_id" => id, "command" => text}

  defp task_path(ctx), do: "/projects/#{ctx.project.id}/tasks/#{ctx.saved.task.id}"

  defp command(view, parent) do
    view
    |> element("#check-form-#{parent} input[name=command_id]")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("value")
    |> hd()
  end

  defp settle(view) do
    render(view)
    render_async(view)
    render_async(view)
    render_async(view)
  end
end
