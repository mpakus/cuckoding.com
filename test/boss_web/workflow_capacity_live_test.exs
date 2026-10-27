defmodule BossWeb.WorkflowCapacityLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Boss.{Deliveries, LocalAccess, Projects, Repo, Runs}
  alias Boss.Deliveries.Scheduling
  alias Boss.Runs.Manager
  alias BossWeb.{ManagerFixture, WorkflowCapacity}

  setup %{conn: conn} do
    owner = self()
    original = :sys.get_state(Manager)
    assert original.active == %{}

    :sys.replace_state(Manager, fn state ->
      %{state | delivery_worker: fn delivery, _, manager -> hold(owner, delivery, manager) end}
    end)

    on_exit(fn -> ManagerFixture.restore(original, [:delivery_worker]) end)

    project =
      Repo.insert!(%Projects.Project{
        name: "Capacity UI",
        root_path: "/capacity-ui",
        git_common_dir: "/capacity-ui/.git",
        specs_path: "/capacity-ui/specs",
        base_branch: "main"
      })

    {:ok, session} = LocalAccess.exchange(LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn, project: project}
  end

  test "capacity is explicit, shared across tabs and retained on reload", c do
    {:ok, first, _} = live(c.conn, "/projects/#{c.project.id}")
    {:ok, second, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(first)
    settle(second)
    assert has_element?(first, "#workflow-capacity-current", "Current limit: 2")
    assert has_element?(first, "#workflow-capacity-help", "across all projects")
    assert has_element?(first, "label[for='workflow-capacity-value']", "Workers")

    first |> form("#workflow-capacity-form", %{"capacity" => "3"}) |> render_change()
    assert {:ok, %{max_parallel_tasks: 2}} = Scheduling.get()
    first |> form("#workflow-capacity-form", %{"capacity" => "3"}) |> render_submit()
    settle(first)
    settle(second)
    assert {:ok, %{max_parallel_tasks: 3}} = Scheduling.get()
    assert has_element?(first, "#workflow-capacity-current", "Current limit: 3")
    assert has_element?(second, "#workflow-capacity-value option[value='3'][selected]")
    assert Repo.aggregate(Deliveries.Delivery, :count) == 0
    assert Repo.aggregate(Runs.Run, :count) == 0

    {:ok, reopened, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(reopened)
    assert has_element?(reopened, "#workflow-capacity-current", "Current limit: 3")
  end

  test "invalid and forged capacity values never write settings", c do
    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(view)

    for value <- ["0", "4", "2x", "", nil, %{"invalid" => "3"}] do
      view |> element("#workflow-capacity-form") |> render_submit(%{"capacity" => value})
      assert has_element?(view, "#workflow-capacity-error", "Choose 1, 2 or 3")
      assert {:ok, %{max_parallel_tasks: 2}} = Scheduling.get()
    end
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "lowering below active workflows refuses without cancelling either worker", c do
    first = start(c.project, "one")
    second = start(c.project, "two")
    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(view)
    view |> form("#workflow-capacity-form", %{"capacity" => "1"}) |> render_submit()
    settle(view)
    assert has_element?(view, "#workflow-capacity-error", "Wait for active workflows")
    assert {:ok, %{max_parallel_tasks: 2}} = Scheduling.get()
    assert Process.alive?(first)
    assert Process.alive?(second)
    send(first, :stop)
    send(second, :stop)
    assert_receive {:finished, _}
    assert_receive {:finished, _}
  end

  test "late settings cannot overwrite a newer confirmed limit or unlock an uncertain request" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        settings: %{max_parallel_tasks: 3, version: 3},
        value: "1",
        pending: %{version: 1, capacity: 1},
        saving: false,
        error: "unconfirmed"
      }
    }

    {:ok, updated} =
      WorkflowCapacity.update(%{settings: %{max_parallel_tasks: 2, version: 2}}, socket)

    assert updated.assigns.settings == %{max_parallel_tasks: 3, version: 3}
    assert updated.assigns.value == "1"
    assert updated.assigns.pending == %{version: 1, capacity: 1}

    {:noreply, completed} =
      WorkflowCapacity.handle_async(
        :save,
        {:ok, {:ok, %{max_parallel_tasks: 1, version: 2}}},
        updated
      )

    assert completed.assigns.settings == %{max_parallel_tasks: 3, version: 3}
    assert completed.assigns.value == "3"
    assert completed.assigns.pending == nil
  end

  test "an uncertain save retains its original value and freezes edits" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        settings: %{max_parallel_tasks: 2, version: 1},
        value: "3",
        pending: %{version: 1, capacity: 3},
        saving: true,
        error: nil
      }
    }

    {:noreply, uncertain} = WorkflowCapacity.handle_async(:save, {:exit, :timeout}, socket)
    assert uncertain.assigns.pending == %{version: 1, capacity: 3}
    assert uncertain.assigns.saving == false
    assert uncertain.assigns.error =~ "Retry the same capacity request"
    {:noreply, frozen} = WorkflowCapacity.handle_event("edit", %{"capacity" => "1"}, uncertain)
    assert frozen.assigns.value == "3"
    assert frozen.assigns.pending == uncertain.assigns.pending
  end

  defp start(project, name) do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: name <> ".md",
        explicit_id: name,
        title: name,
        original_text: "# " <> name
      })

    {:ok, delivery} =
      Deliveries.start(project.id, saved.task.id, Ecto.UUID.generate(), "mix test")

    assert_receive {:started, worker, id} when id == delivery.id, 1_000
    worker
  end

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
    render_async(view)
    render(view)
  end
end
