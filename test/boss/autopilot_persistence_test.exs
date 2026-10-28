defmodule Boss.AutopilotPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo}
  alias Boss.Deliveries.{Autopilot, AutopilotBatch, AutopilotItem, Queue, Request}
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
    {20_261_027_060_000, Boss.Repo.Migrations.AddDeliveryScheduling},
    {20_261_027_070_000, Boss.Repo.Migrations.AddAutopilot}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-autopilot-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    {physical, 0} = System.cmd("/bin/pwd", ["-P"], cd: root)
    root = String.trim(physical)
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

    for args <- [
          ["init", "-b", "main"],
          ["config", "user.name", "Fixture"],
          ["config", "user.email", "fixture@example.invalid"],
          ["commit", "--allow-empty", "-m", "base"],
          ["switch", "-c", "user-work"]
        ] do
      {_, 0} = System.cmd("git", args, cd: root, stderr_to_stdout: true)
    end

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

    %{repo: repo, opts: opts, project: project, tasks: tasks, root: root}
  end

  test "racing duplicate Starts commit one complete immutable selection across Repo restart", c do
    command = Ecto.UUID.generate()

    results =
      race(c.repo, fn -> Autopilot.admit(c.project.id, command, ids(c), "true", "claude") end)

    assert Enum.all?(results, &match?({:ok, _}, &1))
    [{:ok, batch}] = Enum.uniq(results)
    assert Repo.aggregate(AutopilotBatch, :count) == 1
    assert Repo.aggregate(AutopilotItem, :count) == 4
    assert Repo.aggregate(Request, :count) == 4
    assert Repo.aggregate(Deliveries.Delivery, :count) == 0
    assert {:ok, ^batch} = Autopilot.current(c.project.id)
    :ok = stop_supervised(Repo)
    repo = start_supervised!({Repo, c.opts})
    Repo.put_dynamic_repo(repo)
    assert {:ok, ^batch} = Autopilot.current(c.project.id)
    manager = manager(repo, waiting_worker(self()))
    {:ok, paused} = Autopilot.current(c.project.id)
    assert paused.status == "paused" and paused.version == 1
    assert Enum.all?(paused.items, &(&1.request_status == "paused"))
    refute_receive {:started, _, _}, 50
    assert {:ok, _} = Autopilot.resume(c.project.id, batch.id, paused.version, manager)
    assert_receive {:started, delivery, pid}, 3_000

    assert delivery.reviewer == "claude" and
             delivery.spec_revision_id == hd(c.tasks).spec_revision_id

    assert {:ok, _} =
             Autopilot.cancel(c.project.id, batch.id, paused.version, Boss.AutopilotTestActive)

    assert_receive {:stopped, ^pid}
    eventually(fn -> :sys.get_state(manager).active == %{} end)
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1

    assert_raise RuntimeError, "Refusing to discard Autopilot history", fn ->
      Ecto.Migrator.run(Repo, @migrations, :down, to: 20_261_027_070_000, log: false)
    end
  end

  test "concurrent claims serialize even when configured capacity permits three", c do
    {:ok, _} = Boss.Deliveries.Scheduling.update(0, 3, 0)
    {:ok, batch} = Autopilot.admit(c.project.id, Ecto.UUID.generate(), ids(c), "true", "codex")

    results =
      batch.items
      |> Enum.map(fn item ->
        Task.async(fn ->
          Repo.put_dynamic_repo(c.repo)
          Queue.claim(item.request_id)
        end)
      end)
      |> Enum.map(&Task.await(&1, 5_000))

    assert Enum.count(results, &match?({:ok, {:started, _, _}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :busy}, &1)) == 3
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
    assert {:ok, %{max_parallel_tasks: 3}} = Boss.Deliveries.Scheduling.get()
  end

  test "manager retains the automatic slot until actual EXIT and halts on failed receipt", c do
    parent = self()

    worker = fn delivery, _, manager ->
      result = Deliveries.complete(delivery.id, "failed", "Fixture failed")
      send(manager, {:delivery_finished, delivery.id, self(), result})
      send(parent, {:held, delivery, self()})

      receive do
        :release -> :ok
      end
    end

    manager = manager(c.repo, worker)

    {:ok, batch} =
      Autopilot.start(c.project.id, Ecto.UUID.generate(), ids(c), "true", "codex", manager)

    assert_receive {:held, delivery, pid}, 3_000
    eventually(fn -> map_size(:sys.get_state(manager).finished) == 1 end)
    assert map_size(:sys.get_state(manager).active) == 1
    assert {:ok, %{status: "running"}} = Autopilot.current(c.project.id)
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
    send(pid, :release)
    eventually(fn -> match?({:ok, %{status: "blocked"}}, Autopilot.current(c.project.id)) end)
    {:ok, blocked} = Autopilot.current(c.project.id)
    assert blocked.id == batch.id
    assert Enum.count(blocked.items, &(&1.request_status == "cancelled")) == 3
    assert Deliveries.get(c.project.id, delivery.id).status == "failed"
    refute_receive {:held, _, _}, 50
  end

  test "Stop signals live owner while Manager and SQLite writer are stalled", c do
    parent = self()
    manager = manager(c.repo, waiting_worker(parent))

    {:ok, batch} =
      Autopilot.start(c.project.id, Ecto.UUID.generate(), ids(c), "true", "codex", manager)

    assert_receive {:started, _, worker}, 3_000
    :sys.suspend(manager)

    locker =
      Task.async(fn ->
        Repo.put_dynamic_repo(c.repo)

        Repo.transaction(
          fn ->
            send(parent, :locked)

            receive do
              :release -> :ok
            end
          end,
          mode: :immediate
        )
      end)

    assert_receive :locked

    cancel =
      Task.async(fn ->
        Repo.put_dynamic_repo(c.repo)
        Autopilot.cancel(c.project.id, batch.id, 0, Boss.AutopilotTestActive)
      end)

    assert_receive {:stopped, ^worker}, 500
    send(locker.pid, :release)
    assert {:ok, _} = Task.await(locker, 5_000)
    assert {:ok, %{status: "cancelled"}} = Task.await(cancel, 5_000)
    :sys.resume(manager)
    eventually(fn -> :sys.get_state(manager).active == %{} end)
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
  end

  test "lost owner is reconciled and Resume never respawns its interrupted stage", c do
    manager = manager(c.repo, waiting_worker(self()))

    {:ok, batch} =
      Autopilot.start(c.project.id, Ecto.UUID.generate(), ids(c), "true", "codex", manager)

    assert_receive {:started, delivery, worker}, 3_000
    assert Process.alive?(worker)
    :ok = stop_supervised(Manager)
    refute Process.alive?(manager)
    manager = manager(c.repo, waiting_worker(self()))
    {:ok, paused} = Autopilot.current(c.project.id)
    assert paused.status == "paused"
    saved = Deliveries.get(c.project.id, delivery.id)
    assert saved.status == "interrupted" and saved.cleanup == "unknown"
    assert {:ok, _} = Autopilot.resume(c.project.id, batch.id, paused.version, manager)
    eventually(fn -> match?({:ok, %{status: "blocked"}}, Autopilot.current(c.project.id)) end)
    refute_receive {:started, _, _}, 50
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
  end

  test "Resume invalidates a partial dependency sweep cursor without changing authorization", c do
    {:ok, batch} = Autopilot.admit(c.project.id, Ecto.UUID.generate(), ids(c), "true", "codex")
    assert {:ok, paused} = Autopilot.pause(c.project.id, batch.id, batch.version)
    assert {:ok, resumed} = Autopilot.resume_saved(c.project.id, batch.id, paused.version)
    assert resumed.version == 2
    # The old sweep examined every task before Pause; changed dependencies need a fresh sweep.
    assert {:ok, {:launch, :deliver, delivery, _}} =
             Autopilot.advance({batch.id, batch.version, length(c.tasks)})

    assert delivery.task_id == hd(c.tasks).id
  end

  test "empty migration can round trip and lower versions keep their queue guards", c do
    assert [20_261_027_070_000] = Ecto.Migrator.run(Repo, @migrations, :down, step: 1, log: false)
    assert [20_261_027_070_000] = Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)

    assert {:ok, batch} =
             Autopilot.admit(c.project.id, Ecto.UUID.generate(), ids(c), "true", "codex")

    assert length(batch.items) == 4
  end

  defp ids(c), do: Enum.map(c.tasks, & &1.id)

  defp waiting_worker(parent),
    do: fn delivery, _, manager ->
      send(parent, {:started, delivery, self()})

      receive do
        :stop ->
          send(parent, {:stopped, self()})
          result = Deliveries.complete(delivery.id, "cancelled")
          send(manager, {:delivery_finished, delivery.id, self(), result})
      end
    end

  defp manager(repo, worker),
    do:
      start_supervised!(
        {Manager,
         [name: nil, repo: repo, registry: Boss.AutopilotTestActive, delivery_worker: worker]}
      )

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

  defp eventually(fun, left \\ 300)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, left),
    do:
      if(fun.(),
        do: :ok,
        else:
          (
            Process.sleep(10)
            eventually(fun, left - 1)
          )
      )
end
