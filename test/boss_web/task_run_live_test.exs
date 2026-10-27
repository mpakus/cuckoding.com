defmodule BossWeb.TaskRunLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Boss.{LocalAccess, Projects, Repo, Runs}
  alias Boss.Runs.Manager
  alias BossWeb.ManagerFixture

  setup %{conn: conn} do
    test_pid = self()
    original = :sys.get_state(Manager)
    assert :sys.get_state(Manager).active == %{}

    :sys.replace_state(Manager, fn state ->
      %{state | worker: fn run, _repo, manager -> fake_worker(test_pid, run, manager) end}
    end)

    on_exit(fn -> ManagerFixture.restore(original, [:worker]) end)

    project = project("run-ui")
    saved = spec(project, "one", "PINNED_SOURCE")
    {:ok, session} = LocalAccess.exchange(LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn, project: project, saved: saved}
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "Start pins the task snapshot, deduplicates, survives drawer close and shows unverified output",
       ctx do
    spec(ctx.project, "one", "LATEST_SOURCE")
    {:ok, view, _} = live(ctx.conn, task_path(ctx) <> "?revision=2")
    settle(view)
    assert has_element?(view, "#task-source", "LATEST_SOURCE")
    assert has_element?(view, "#run-snapshot", "snapshot revision 1")
    command = command(view)
    render_click(view, "start_run", %{"command-id" => command, "task_id" => "999"})
    assert_receive {:working, worker, run}, 1_000
    settle(view)
    assert run.spec_revision_id == ctx.saved.task.spec_revision_id
    assert run.task_id == ctx.saved.task.id
    render_click(view, "start_run", %{"command-id" => command})
    assert length(Runs.list(ctx.project.id, ctx.saved.task.id)) == 1
    assert has_element?(view, "#start-codex[disabled]")

    render_patch(view, "/projects/#{ctx.project.id}")
    assert Process.alive?(worker)
    render_patch(view, task_path(ctx))
    settle(view)
    assert has_element?(view, "#run-#{run.id}", "Preparing workspace")

    finish(worker,
      status: "finished",
      summary: %{
        "event_count" => 3,
        "stdout_bytes" => 42,
        "stderr_bytes" => 4,
        "usage" => %{"input_tokens" => 7, "output_tokens" => 2},
        "events" => [
          %{"sequence" => 1, "type" => "turn.completed"},
          %{"sequence" => 2, "type" => "PRIVATE_OUTPUT"}
        ]
      },
      workspace: %{"path" => "/retained/a-long-workspace/<escaped>"}
    )

    settle(view)
    assert has_element?(view, "#run-#{run.id}", "Codex finished — unverified")
    assert has_element?(view, "#run-#{run.id}", "3 events · 42 stdout bytes · 4 stderr bytes")
    assert has_element?(view, "#run-#{run.id}", "turn.completed")
    refute render(view) =~ "PRIVATE_OUTPUT"
    assert has_element?(view, "#run-#{run.id} code", "/retained/a-long-workspace/<escaped>")
    refute has_element?(view, "#start-codex[disabled]")
    refute command(view) == command
    assert Repo.get!(Boss.Tasks.Task, ctx.saved.task.id).state == "new"
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "unknown admission keeps the command ID for retry and the application admits once", ctx do
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    command = command(view)
    :sys.suspend(Manager)
    on_exit(fn -> :sys.resume(Manager) end)
    render_click(view, "start_run", %{"command-id" => command})

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, :start_run, :kill)}
    end)

    settle(view)
    assert has_element?(view, "#run-error", "could not be confirmed")
    assert command(view) == command
    render_click(view, "start_run", %{"command-id" => command})
    :sys.resume(Manager)
    assert_receive {:working, worker, run}, 1_000
    settle(view)
    assert run.command_id == command
    assert length(Runs.list(ctx.project.id, ctx.saved.task.id)) == 1
    refute_receive {:working, _, _}, 50
    finish(worker)
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "Stop only accepts a displayed task attempt and remains available after reconnect", ctx do
    other = spec(ctx.project, "other", "OTHER_SOURCE")
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    view |> element("#start-codex") |> render_click()
    assert_receive {:working, worker, run}, 1_000
    settle(view)
    render_patch(view, "/projects/#{ctx.project.id}/tasks/#{other.task.id}")
    settle(view)
    render_click(view, "stop_run", %{"run-id" => run.id})
    assert Process.alive?(worker)
    assert {:error, :not_running} = Runs.stop(ctx.project.id + 1, run.id)
    {:ok, reconnected, _} = live(ctx.conn, task_path(ctx))
    settle(reconnected)
    reconnected |> element("#stop-run-#{run.id}") |> render_click()
    assert_receive {:fixture_finished, id}, 1_000
    assert id == run.id
    settle(reconnected)
    assert has_element?(reconnected, "#run-#{run.id}", "Cancelled — workspace retained")
    refute has_element?(reconnected, "#stop-run-#{run.id}")
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "unknown cleanup blocks its task and admission elsewhere without exposing foreign history",
       ctx do
    {:ok, {:new, run}} = Runs.admit(ctx.project.id, ctx.saved.task.id, Ecto.UUID.generate())

    {:ok, _} =
      Runs.update(run.id, status: "interrupted", cleanup: "unknown", reason: "Owner lost.")

    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    assert has_element?(view, "#run-cleanup-warning", "new runs are blocked")
    assert has_element?(view, "#start-codex[disabled]")

    another = project("another")
    saved = spec(another, "other", "OTHER_SOURCE")
    {:ok, other, _} = live(ctx.conn, "/projects/#{another.id}/tasks/#{saved.task.id}")
    settle(other)
    other |> element("#start-codex") |> render_click()
    settle(other)
    assert has_element?(other, "#run-error", "cleanup needs attention")
    refute has_element?(other, "#run-#{run.id}")
    refute_receive {:working, _, _}, 50
  end

  test "history is bounded and unsupported platforms have no enabled Start", ctx do
    for _ <- 1..12 do
      {:ok, {:new, run}} = Runs.admit(ctx.project.id, ctx.saved.task.id, Ecto.UUID.generate())

      {:ok, _} =
        Runs.update(run.id,
          status: "finished",
          cleanup: "not_started",
          summary: %{"usage" => %{}}
        )
    end

    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)

    refute render(view) =~ "Tokens:"

    assert render(view)
           |> LazyHTML.from_document()
           |> LazyHTML.query("#run-attempts > li")
           |> Enum.count() == 10

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.Component.assign(state.socket, run_supported: false)}
    end)

    render_click(view, "start_run", %{"command-id" => command(view)})
    assert has_element?(view, "#start-codex[disabled]")
    assert has_element?(view, "#task-runs", "require macOS")
    refute_receive {:working, _, _}, 50
  end

  test "task and run details share the actual Repo and a read transaction", ctx do
    observer = make_ref()
    :ok = :telemetry.attach(observer, [:boss, :repo, :query], &__MODULE__.observe_read/4, self())
    on_exit(fn -> :telemetry.detach(observer) end)
    {:ok, view, _} = live(ctx.conn, task_path(ctx))
    settle(view)
    repo = Process.whereis(Repo)
    assert_receive {:detail_read, :task, ^repo, true}
    assert_receive {:detail_read, :runs, ^repo, true}
  end

  def observe_read(_, _, %{query: query}, owner) do
    if String.starts_with?(query, "SELECT") do
      kind =
        cond do
          String.contains?(query, ~s(FROM "tasks")) -> :task
          String.contains?(query, ~s(FROM "agent_runs")) -> :runs
          true -> nil
        end

      if kind,
        do: send(owner, {:detail_read, kind, Repo.get_dynamic_repo(), Repo.in_transaction?()})
    end
  end

  defp fake_worker(test_pid, run, manager) do
    send(test_pid, {:working, self(), run})

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
          [status: "finished", cleanup: "not_started", finished_at: DateTime.utc_now()],
          attrs
        )
      )

    send(manager, {:run_finished, run.id, self(), result})
    send(test_pid, {:fixture_finished, run.id})
  end

  defp finish(worker, attrs \\ []) do
    send(worker, {:finish, attrs})
    assert_receive {:fixture_finished, _}, 1_000
    :sys.get_state(Manager)
  end

  defp project(name),
    do:
      Repo.insert!(%Projects.Project{
        name: name,
        root_path: "/#{name}",
        git_common_dir: "/#{name}/.git",
        specs_path: "/#{name}/specs",
        base_branch: "main"
      })

  defp spec(project, name, source) do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: "#{name}.md",
        title: name,
        original_text: source
      })

    saved
  end

  defp task_path(ctx), do: "/projects/#{ctx.project.id}/tasks/#{ctx.saved.task.id}"

  defp command(view),
    do:
      view
      |> element("#start-codex")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("phx-value-command-id")
      |> hd()

  defp settle(view) do
    render(view)
    render_async(view)
    render_async(view)
    render_async(view)
  end
end
