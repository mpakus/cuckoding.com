defmodule BossWeb.ManagerFixtureTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo}
  alias Boss.Deliveries.Queue
  alias Boss.Runs.Manager
  alias BossWeb.ManagerFixture
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> if Process.alive?(owner), do: Sandbox.stop_owner(owner) end)
    original = :sys.get_state(Manager)
    assert original.active == %{}
    on_exit(fn -> ManagerFixture.restore(original, [:delivery_worker]) end)

    project =
      Repo.insert!(%Projects.Project{
        name: "Fixture lifecycle",
        root_path: "/fixture-lifecycle",
        git_common_dir: "/fixture-lifecycle/.git",
        specs_path: "/fixture-lifecycle/specs",
        base_branch: "main"
      })

    %{owner: owner, original: original, project: project}
  end

  test "queued polling cannot outlive its sandbox owner, including already delivered timer messages",
       c do
    task = spec(c.project, "waiting", "---\ndepends_on: [missing]\n---\n# Wait")
    {:ok, _} = Queue.enqueue(c.project.id, task.id, Ecto.UUID.generate(), "mix test", "codex")
    manager = Process.whereis(Manager)
    {timer, tag} = :sys.get_state(manager).queue_timer
    send(manager, {:queue_tick, tag})
    ManagerFixture.restore(c.original, [:delivery_worker])
    assert Process.read_timer(timer) == false
    monitor = Process.monitor(manager)
    Sandbox.stop_owner(c.owner)
    send(manager, {:queue_tick, tag})
    assert_idle(manager)
    # The old periodic delay is 500ms; a future tick must be cancelled too.
    refute_receive {:DOWN, ^monitor, :process, ^manager, _}, 600
    assert_idle(manager)
    Process.demonitor(monitor, [:flush])
  end

  test "all fixture workers stop before ownership closes and terminal messages cannot rearm polling",
       c do
    test_pid = self()

    :sys.replace_state(Manager, fn state ->
      %{
        state
        | delivery_worker: fn delivery, _, manager ->
            send(test_pid, {:working, self(), delivery})

            receive do
              :stop ->
                result = Deliveries.complete(delivery.id, "cancelled")
                send(manager, {:delivery_finished, delivery.id, self(), result})
            end
          end
      }
    end)

    first = spec(c.project, "first", "# First")
    second = spec(c.project, "second", "# Second")
    {:ok, _} = Deliveries.start(c.project.id, first.id, Ecto.UUID.generate(), "mix test")
    {:ok, _} = Deliveries.start(c.project.id, second.id, Ecto.UUID.generate(), "mix test")
    assert_receive {:working, first_pid, first_delivery}, 1_000
    assert_receive {:working, second_pid, second_delivery}, 1_000
    manager = Process.whereis(Manager)
    batch = Ecto.UUID.generate()

    :sys.replace_state(manager, fn state ->
      :ets.insert(state.registry, {{:autopilot, batch}, c.project.id, first_pid})
      %{state | autopilot_cursor: {batch, 0, 1}}
    end)

    assert :ets.lookup(Boss.Runs.Active, {:autopilot, batch}) != []
    ManagerFixture.restore(c.original, [:delivery_worker])
    refute Process.alive?(first_pid)
    refute Process.alive?(second_pid)
    assert hd(Deliveries.list(c.project.id, first.id)).status == "cancelled"
    assert hd(Deliveries.list(c.project.id, second.id)).status == "cancelled"
    Sandbox.stop_owner(c.owner)

    for {worker, delivery} <- [{first_pid, first_delivery}, {second_pid, second_delivery}] do
      send(manager, {:delivery_finished, delivery.id, worker, {:ok, delivery}})
      send(manager, {:EXIT, worker, :normal})
    end

    assert_idle(manager)
  end

  defp assert_idle(manager) do
    assert Process.whereis(Manager) == manager
    state = :sys.get_state(manager)
    assert state.active == %{}
    assert state.finished == %{}
    assert state.queue_timer == nil
    assert state.queue_cursor == nil
    assert state.autopilot_cursor == nil
    assert :ets.tab2list(state.registry) == []
  end

  defp spec(project, name, source) do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: "#{name}.md",
        title: name,
        original_text: source
      })

    saved.task
  end
end
