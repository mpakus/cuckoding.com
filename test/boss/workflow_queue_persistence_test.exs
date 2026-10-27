defmodule Boss.WorkflowQueuePersistenceTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Boss.{Deliveries, Projects, Repo, Runs, Tasks}
  alias Boss.Deliveries.{Queue, Request}
  alias Boss.Runs.Manager
  @moduletag capture_log: true
  @migrations [
    {20_261_025_180_000, Boss.Repo.Migrations.CreateProjects},
    {20_261_025_220_000, Boss.Repo.Migrations.CreateSpecRevisions},
    {20_261_025_230_000, Boss.Repo.Migrations.TrackMissingSpecs},
    {20_261_026_010_000, Boss.Repo.Migrations.CreateTaskEvents},
    {20_261_026_040_000, Boss.Repo.Migrations.CreateAgentRuns},
    {20_261_026_060_000, Boss.Repo.Migrations.AddManualChecks},
    {20_261_026_160_000, Boss.Repo.Migrations.AddManualReviews},
    {20_261_026_220_000, Boss.Repo.Migrations.CreateDeliveries},
    {20_261_027_010_000, Boss.Repo.Migrations.AddTaskRevisionAdoption},
    {20_261_027_020_000, Boss.Repo.Migrations.PreserveHistoricalRunPins},
    {20_261_027_030_000, Boss.Repo.Migrations.PinDeliveryReviewer},
    {20_261_027_040_000, Boss.Repo.Migrations.AddWorkflowQueue},
    {20_261_027_050_000, Boss.Repo.Migrations.AddMergeIntegrationEvidence},
    {20_261_027_060_000, Boss.Repo.Migrations.AddDeliveryScheduling}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-queue-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, lock} = Boss.DataDirectory.acquire(root)
    on_exit(fn -> Boss.DataDirectory.release(lock) end)

    opts = [
      name: nil,
      database: Path.join(root, "boss.db"),
      pool: DBConnection.ConnectionPool,
      pool_size: 2
    ]

    repo = start_supervised!({Repo, opts})
    Repo.put_dynamic_repo(repo)
    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)

    project =
      Repo.insert!(%Projects.Project{
        name: "Queue",
        root_path: root,
        git_common_dir: Path.join(root, ".git"),
        specs_path: root,
        base_branch: "main"
      })

    tasks =
      for n <- 1..4 do
        {:ok, %{task: task}} =
          Projects.record_spec(project.id, %{
            relative_path: "task#{n}.md",
            title: "Task#{n}",
            original_text: "# Task#{n}"
          })

        task
      end

    %{repo: repo, opts: opts, project: project, tasks: tasks}
  end

  test "racing duplicate enqueue and claims produce one committed delivery", c do
    task = hd(c.tasks)
    command = Ecto.UUID.generate()
    queued = race(c.repo, fn -> Queue.admit(c.project.id, task.id, command, "true", "claude") end)
    assert Enum.all?(queued, &match?({:ok, %Request{}}, &1))
    [{:ok, request}] = Enum.uniq(queued)
    assert Repo.aggregate(Request, :count) == 1
    assert Tasks.get_task!(task.id).state == "new"
    claims = race(c.repo, fn -> Queue.claim(request.id) end)
    assert Enum.count(claims, &match?({:ok, {:started, _, _}}, &1)) == 1
    assert Enum.count(claims, &match?({:ok, {:existing, _, _}}, &1)) == 3
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
    assert length(Tasks.list_events(task.id)) == 1
    saved = Repo.get!(Request, request.id)
    assert saved.status == "started"
    assert Deliveries.get(c.project.id, saved.delivery_id).reviewer == "claude"
    :ok = stop_supervised(Repo)
    repo = start_supervised!({Repo, c.opts})
    Repo.put_dynamic_repo(repo)
    assert Repo.get!(Request, request.id) == saved
    assert {:ok, {:existing, ^saved, _}} = Queue.claim(request.id)

    assert_raise RuntimeError, "Refusing to discard queue history", fn ->
      Ecto.Migrator.run(Repo, @migrations, :down, to: 20_261_027_040_000, log: false)
    end
  end

  test "racing independent claims never exceed two active deliveries", c do
    requests = Enum.map(c.tasks, &enqueue(c.project, &1))

    results =
      requests
      |> Enum.map(fn request ->
        Task.async(fn ->
          Repo.put_dynamic_repo(c.repo)
          Queue.claim(request.id)
        end)
      end)
      |> Enum.map(&Task.await(&1, 5_000))

    assert Enum.count(results, &match?({:ok, {:started, _, _}}, &1)) == 2
    assert Enum.count(results, &match?({:error, :busy}, &1)) == 2
    assert Repo.aggregate(Deliveries.Delivery, :count) == 2
    assert Repo.aggregate(from(r in Request, where: r.status == "queued"), :count) == 2
  end

  test "manager retains slots and Stop routing until the exact worker exits", c do
    parent = self()

    worker = fn delivery, _repo, manager ->
      send(parent, {:started, delivery.id, self()})

      receive do
        :finish ->
          result = Deliveries.complete(delivery.id, "cancelled")
          send(manager, {:delivery_finished, delivery.id, self(), result})
          send(parent, {:receipt, delivery.id})

          receive do
            :exit -> :ok
          end

        :stop ->
          result = Deliveries.complete(delivery.id, "cancelled")
          send(manager, {:delivery_finished, delivery.id, self(), result})
      end
    end

    manager = manager(c.repo, worker)
    [a, b, t, _] = c.tasks
    {:ok, first} = Deliveries.start(c.project.id, a.id, Ecto.UUID.generate(), "true", manager)
    {:ok, second} = Deliveries.start(c.project.id, b.id, Ecto.UUID.generate(), "true", manager)
    first_id = first.id
    second_id = second.id
    assert_receive {:started, ^first_id, first_pid}
    assert_receive {:started, ^second_id, second_pid}
    send(manager, {:delivery_finished, first.id, self(), {:ok, first}})
    send(manager, {:delivery_finished, Ecto.UUID.generate(), first_pid, {:ok, first}})
    send(first_pid, :finish)
    send(second_pid, :finish)
    assert_receive {:receipt, ^first_id}
    assert_receive {:receipt, ^second_id}
    eventually(fn -> map_size(:sys.get_state(manager).finished) == 2 end)
    assert map_size(:sys.get_state(manager).active) == 2

    assert {:error, :busy} =
             Deliveries.start(c.project.id, t.id, Ecto.UUID.generate(), "true", manager)

    assert {:error, :busy} = Runs.start(c.project.id, t.id, Ecto.UUID.generate(), manager)

    {:ok, request} =
      Queue.enqueue(c.project.id, t.id, Ecto.UUID.generate(), "true", "codex", manager)

    refute_receive {:started, _, _}, 100
    assert Repo.get!(Request, request.id).status == "queued"
    send(first_pid, :exit)
    assert_receive {:started, third_id, third_pid}, 1_500
    assert Process.alive?(second_pid)
    assert {:ok, _} = Queue.resume(c.project.id, request.id, manager)
    refute_receive {:started, _, _}, 50
    assert Repo.get!(Request, request.id).delivery_id == third_id
    assert :ok = Runs.stop(c.project.id, third_id, Boss.QueueTestActive)
    eventually(fn -> not Process.alive?(third_pid) end)
    assert Process.alive?(second_pid)
    send(second_pid, :exit)
    eventually(fn -> :sys.get_state(manager).active == %{} end)
  end

  test "restart pauses committed authorization and only explicit resume dispatches", c do
    task = hd(c.tasks)
    request = enqueue(c.project, task)
    parent = self()

    worker = fn delivery, _repo, manager ->
      send(parent, {:started, delivery})

      receive do
        :stop ->
          result = Deliveries.complete(delivery.id, "cancelled")
          send(manager, {:delivery_finished, delivery.id, self(), result})
      end
    end

    manager = manager(c.repo, worker)
    paused = Repo.get!(Request, request.id)
    assert paused.status == "paused"
    refute_receive {:started, _}, 100
    assert Tasks.get_task!(task.id).state == "new"
    assert {:ok, resumed} = Queue.resume(c.project.id, request.id, manager)
    assert resumed.command_id == request.command_id
    assert_receive {:started, delivery}, 1_500
    assert delivery.command_id == request.command_id
    assert delivery.check_config == request.check_config
    assert :ok = Runs.stop(c.project.id, delivery.id, Boss.QueueTestActive)
    eventually(fn -> :sys.get_state(manager).active == %{} end)
  end

  test "queued source blocks adoption at both context and SQL boundary", c do
    task = hd(c.tasks)
    request = enqueue(c.project, task)

    {:ok, %{revision: target}} =
      Projects.record_spec(c.project.id, %{
        relative_path: "task1.md",
        title: "Changed",
        original_text: "# Changed"
      })

    command = %{
      action: "adopt_revision",
      project_id: c.project.id,
      spec_revision_id: target.id,
      expected_version: task.state_version,
      command_id: Ecto.UUID.generate()
    }

    assert {:error, :busy} = Tasks.transition(task.id, command)

    assert {:error, _} =
             Repo.query("UPDATE tasks SET spec_revision_id=? WHERE id=?", [target.id, task.id])

    assert {:ok, _} = Queue.cancel(c.project.id, request.id)
    assert {:ok, _} = Tasks.transition(task.id, command)
  end

  test "cancel racing claim resolves to exactly one committed outcome", c do
    request = enqueue(c.project, hd(c.tasks))

    jobs =
      for operation <- [:claim, :cancel] do
        Task.async(fn ->
          Repo.put_dynamic_repo(c.repo)

          case operation do
            :claim -> Queue.claim(request.id)
            :cancel -> Queue.cancel(c.project.id, request.id)
          end
        end)
      end

    [claimed, cancelled] = Enum.map(jobs, &Task.await(&1, 5_000))
    saved = Repo.get!(Request, request.id)

    case saved.status do
      "started" ->
        assert {:ok, {:started, ^saved, _}} = claimed
        assert cancelled == {:error, :already_started}
        assert Repo.aggregate(Deliveries.Delivery, :count) == 1

      "cancelled" ->
        assert claimed == {:error, :request_unavailable}
        assert {:ok, ^saved} = cancelled
        assert Repo.aggregate(Deliveries.Delivery, :count) == 0
    end
  end

  test "downgrade refuses concurrent live data even without queued history", c do
    for task <- Enum.take(c.tasks, 2) do
      assert {:ok, {:new, _}} =
               Deliveries.admit(c.project.id, task.id, Ecto.UUID.generate(), "true")
    end

    assert_raise RuntimeError, "Refusing to discard concurrent delivery capacity", fn ->
      Ecto.Migrator.run(Repo, @migrations, :down, to: 20_261_027_040_000, log: false)
    end
  end

  defp manager(repo, worker),
    do:
      start_supervised!(
        {Manager,
         [name: nil, repo: repo, registry: Boss.QueueTestActive, delivery_worker: worker]}
      )

  defp enqueue(project, task) do
    {:ok, request} = Queue.admit(project.id, task.id, Ecto.UUID.generate(), "true", "codex")
    request
  end

  defp race(repo, fun),
    do:
      1..4
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Repo.put_dynamic_repo(repo)
          fun.()
        end)
      end)
      |> Enum.map(&Task.await(&1, 5_000))

  defp eventually(fun, n \\ 150)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, n) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          eventually(fun, n - 1)
        )
  end
end
