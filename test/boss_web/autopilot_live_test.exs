defmodule BossWeb.AutopilotLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Boss.{Deliveries, LocalAccess, Projects, Repo, Runs, Tasks}
  alias Boss.Deliveries.Autopilot, as: Engine
  alias Boss.Runs.Manager
  alias BossWeb.{Autopilot, ManagerFixture}

  setup %{conn: conn} do
    owner = self()
    original = :sys.get_state(Manager)
    assert original.active == %{}

    :sys.replace_state(Manager, fn state ->
      %{state | delivery_worker: fn delivery, _, manager -> hold(owner, delivery, manager) end}
    end)

    on_exit(fn -> ManagerFixture.restore(original, [:delivery_worker]) end)

    project = project("Autopilot UI")
    first = task(project, "First")
    second = task(project, "Second")
    {:ok, session} = LocalAccess.exchange(LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn, project: project, first: first, second: second}
  end

  test "opening and editing is read-only; explicit Start pins the whole current Backlog", c do
    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(view)
    assert has_element?(view, "#autopilot-content[hidden]")
    refute has_element?(view, "#autopilot-form input[type=checkbox]")
    assert has_element?(view, "#autopilot-selection-count", "2 tasks in Backlog")
    view |> element("#project-autopilot") |> render_click()
    assert has_element?(view, "#open-autopilot[aria-expanded=true]")
    refute has_element?(view, "#autopilot-content[hidden]")
    assert has_element?(view, "#autopilot-authorization", "automatic integration")
    assert has_element?(view, "#autopilot-provider-help", "may incur charges")

    params = params()
    view |> form("#autopilot-form", params) |> render_change()
    refute has_element?(view, "#start-autopilot[disabled]")
    assert {:ok, nil} = Engine.current(c.project.id)
    assert Repo.aggregate(Deliveries.Delivery, :count) == 0

    view |> form("#autopilot-form", params) |> render_submit()
    assert_receive {:started, _, _}, 1_500
    settle(view)
    assert {:ok, batch} = Engine.current(c.project.id)
    assert Enum.map(batch.items, & &1.task_id) == [c.first.task.id, c.second.task.id]
    assert batch.check_config["argv"] == ["mix", "test"]
    assert batch.reviewer == "codex"
    assert has_element?(view, "#autopilot-status", "Running")
    assert has_element?(view, "#autopilot-item-#{c.first.task.id}", "First")
    assert has_element?(view, "#autopilot-item-#{c.second.task.id}", "Second")
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
    assert Repo.aggregate(Runs.Run, :count) == 0

    {:ok, reopened, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(reopened)
    assert has_element?(reopened, "#autopilot-status", "Running")
    refute has_element?(reopened, "#autopilot-content[hidden]")
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
  end

  test "Pause and Resume are shared across tabs; Stop cancels active work and the selection", c do
    {:ok, first, _} = live(c.conn, "/projects/#{c.project.id}")
    {:ok, second, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(first)
    settle(second)
    first |> element("#open-autopilot") |> render_click()
    first |> form("#autopilot-form", params()) |> render_submit()
    assert_receive {:started, worker, _}, 1_500
    settle(first)
    settle(second)
    first |> element("#pause-autopilot") |> render_click()
    settle(first)
    settle(second)
    assert has_element?(second, "#autopilot-status", "Paused")
    assert Process.alive?(worker)
    refute_receive {:started, _, _}, 100

    first |> element("#resume-autopilot") |> render_click()
    settle(first)
    settle(second)
    assert has_element?(second, "#autopilot-status", "Running")
    first |> element("#stop-autopilot") |> render_click()
    assert_receive {:finished, _}, 1_500
    settle(first)
    settle(second)
    assert has_element?(second, "#autopilot-status", "Cancelled")
    assert {:ok, %{status: "cancelled"}} = Engine.current(c.project.id)
    refute_receive {:started, _, _}, 100
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
  end

  test "submitted task IDs cannot replace the complete project Backlog", c do
    outsider = task(project("Other"), "Outside")
    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(view)
    view |> element("#project-autopilot") |> render_click()

    view
    |> element("#autopilot-form")
    |> render_submit(Map.put(params(), "tasks", [to_string(outsider.task.id)]))

    assert_receive {:started, _, _}, 1_500
    settle(view)
    assert {:ok, batch} = Engine.current(c.project.id)
    assert Enum.map(batch.items, & &1.task_id) == [c.first.task.id, c.second.task.id]
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
  end

  test "empty Backlog and tasks outside New never receive automatic authorization", c do
    for task <- [c.first.task, c.second.task] do
      assert {:ok, _} =
               Tasks.transition(task.id, %{
                 action: "cancel",
                 expected_version: 0,
                 command_id: Ecto.UUID.generate(),
                 reason: "User cancelled"
               })
    end

    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(view)
    view |> element("#project-autopilot") |> render_click()
    assert has_element?(view, "#start-autopilot[disabled]")
    assert has_element?(view, "#autopilot-selection-count", "0 tasks in Backlog")
    view |> element("#autopilot-form") |> render_submit(params())
    assert has_element?(view, "#autopilot-error", "requires 1–256 tasks")
    assert {:ok, nil} = Engine.current(c.project.id)
    assert Repo.aggregate(Deliveries.Delivery, :count) == 0
  end

  test "invalid check commands produce a recoverable error without authorizing the Backlog", c do
    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(view)
    view |> element("#project-autopilot") |> render_click()
    view |> form("#autopilot-form", Map.put(params(), "command", "")) |> render_submit()
    settle(view)
    assert has_element?(view, "#autopilot-error", "valid check command")
    assert has_element?(view, "#autopilot-task-#{c.first.task.id}", "First")
    refute has_element?(view, "#autopilot-form fieldset[disabled]")
    assert {:ok, nil} = Engine.current(c.project.id)
  end

  test "unknown outcomes freeze the original UUID and inputs instead of silently changing authorization" do
    request = %{
      kind: :start,
      id: Ecto.UUID.generate(),
      tasks: [10],
      text: "mix test",
      reviewer: "claude"
    }

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        pending: request,
        acting: true,
        error: nil,
        selected: ["10"],
        text: "mix test",
        reviewer: "claude"
      }
    }

    {:noreply, uncertain} =
      Autopilot.handle_async({:action, request.id}, {:exit, :timeout}, socket)

    assert uncertain.assigns.pending == request
    assert uncertain.assigns.acting == false
    assert uncertain.assigns.error =~ "Retry the same saved"

    {:noreply, frozen} =
      Autopilot.handle_event(
        "edit",
        %{"tasks" => ["20"], "command" => "false", "reviewer" => "codex"},
        uncertain
      )

    assert frozen.assigns.pending.tasks == [10]
    assert frozen.assigns.text == "mix test"
    assert frozen.assigns.reviewer == "claude"
    assert frozen.assigns.pending == request
  end

  test "a read begun before an action cannot replace its newer saved status" do
    batch = %{id: "latest", status: "running"}
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, generation: 3, batch: batch}}
    {:noreply, same} = Autopilot.handle_async({:load, 2}, {:ok, {:ok, nil}}, socket)
    assert same.assigns.batch == batch
  end

  test "unchanged project renders preserve an unsaved command", c do
    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(view)
    view |> element("#project-autopilot") |> render_click()
    view |> form("#autopilot-form", params()) |> render_change()
    Runs.broadcast(%{project_id: c.project.id})
    settle(view)
    assert has_element?(view, "#autopilot-task-#{c.first.task.id}", "First")
    assert has_element?(view, "#autopilot-command[value='mix test']")
    assert {:ok, nil} = Engine.current(c.project.id)
  end

  test "restart pause updates the open panel without a page reload", c do
    {:ok, _} =
      Engine.admit(
        c.project.id,
        Ecto.UUID.generate(),
        [c.first.task.id, c.second.task.id],
        "true",
        "codex"
      )

    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(view)
    assert has_element?(view, "#autopilot-status", "Running")
    assert {:ok, [_]} = Engine.pause_on_restart()
    settle(view)
    assert has_element?(view, "#autopilot-status", "Paused")
    assert has_element?(view, "#resume-autopilot")
    refute_receive {:started, _, _}, 30
  end

  for blocker <- [:manual, :managed, :paused] do
    test "#{blocker} ownership elsewhere refuses Start without suggesting waiting clears quarantine",
         c do
      other = project("Other project")
      saved = task(other, "Other task")

      case unquote(blocker) do
        :manual ->
          {:ok, {:new, _}} = Runs.admit(other.id, saved.task.id, Ecto.UUID.generate())
          {:ok, _} = Runs.reconcile()

        :managed ->
          {:ok, {:new, delivery}} =
            Deliveries.admit(other.id, saved.task.id, Ecto.UUID.generate(), "true")

          {:ok, _} = Deliveries.interrupt(delivery.id)

        :paused ->
          {:ok, batch} =
            Engine.admit(other.id, Ecto.UUID.generate(), [saved.task.id], "true", "codex")

          {:ok, _} = Engine.pause(other.id, batch.id, batch.version)
      end

      schemas = [
        Runs.Run,
        Deliveries.Delivery,
        Boss.Deliveries.AutopilotBatch,
        Boss.Deliveries.Request
      ]

      before_start = Enum.map(schemas, &Repo.all/1)
      {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}")
      settle(view)
      view |> element("#project-autopilot") |> render_click()
      view |> form("#autopilot-form", params()) |> render_submit()
      settle(view)
      assert has_element?(view, "#autopilot-error", "running or paused")
      assert has_element?(view, "#autopilot-error", "cleanup is unconfirmed")
      refute has_element?(view, "#autopilot-error", "Wait or pause it first")
      assert Enum.map(schemas, &Repo.all/1) == before_start
      assert {:ok, nil} = Engine.current(c.project.id)
      refute_receive {:started, _, _}, 30
    end
  end

  defp project(name) do
    root = Path.join(System.tmp_dir!(), "boss-autopilot-ui-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {canonical, 0} = System.cmd("pwd", ["-P"], cd: root)
    root = String.trim(canonical)
    File.mkdir!(Path.join(root, "specs"))

    for args <- [
          ["init", "-q", "-b", "main"],
          ["config", "user.name", "Fixture"],
          ["config", "user.email", "fixture@example.test"],
          ["commit", "-q", "--allow-empty", "-m", "base"],
          ["checkout", "-q", "-b", "user-work"]
        ] do
      assert {_, 0} = System.cmd("git", args, cd: root, stderr_to_stdout: true)
    end

    Repo.insert!(%Projects.Project{
      name: name,
      root_path: root,
      git_common_dir: Path.join(root, ".git"),
      specs_path: Path.join(root, "specs"),
      base_branch: "main"
    })
  end

  defp task(project, name) do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: name <> ".md",
        explicit_id: name,
        title: name,
        original_text: "# " <> name
      })

    saved
  end

  defp params, do: %{"command" => "mix test", "reviewer" => "codex"}

  defp hold(owner, delivery, manager) do
    send(owner, {:started, self(), delivery.id})

    receive do
      :stop -> :ok
    after
      10_000 -> :ok
    end

    result = Deliveries.complete(delivery.id, "cancelled")
    send(manager, {:delivery_finished, delivery.id, self(), result})
    send(owner, {:finished, delivery.id})
  end

  defp settle(view) do
    render_async(view, 2_000)
    render(view)
    render_async(view, 2_000)
  end
end
