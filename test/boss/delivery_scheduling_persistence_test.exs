defmodule Boss.DeliverySchedulingPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo}
  alias Boss.Deliveries.{Scheduling, Step}
  alias Boss.Runs.Manager
  @moduletag capture_log: true
  @base String.duplicate("a", 40)
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
    root = Path.join(System.tmp_dir!(), "boss-scheduling-#{Ecto.UUID.generate()}")
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
        name: "Scheduling",
        root_path: root,
        git_common_dir: Path.join(root, ".git"),
        specs_path: root,
        base_branch: "main"
      })

    tasks =
      for n <- 1..4 do
        {:ok, %{task: task}} =
          Projects.record_spec(project.id, %{
            relative_path: "#{n}.md",
            title: "Task#{n}",
            original_text: "# Task#{n}"
          })

        task
      end

    %{repo: repo, opts: opts, project: project, tasks: tasks}
  end

  test "racing settings use version CAS, survive restart and constrain concurrent admission", c do
    results = race(c.repo, [1, 3], fn capacity -> Scheduling.update(0, capacity, 0) end)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :stale_settings}, &1)) == 1
    assert {:ok, selected} = Scheduling.get()
    restart(c.opts)
    assert {:ok, ^selected} = Scheduling.get()
    assert {:ok, %{max_parallel_tasks: 3} = saved} = Scheduling.update(selected.version, 3, 0)
    repo = Repo.get_dynamic_repo()

    results =
      race(repo, c.tasks, fn task ->
        Deliveries.admit(c.project.id, task.id, Ecto.UUID.generate(), "true")
      end)

    assert Enum.count(results, &match?({:ok, {:new, _}}, &1)) == 3
    assert Enum.count(results, &match?({:error, :busy}, &1)) == 1
    assert Repo.aggregate(Deliveries.Delivery, :count) == 3
    assert {:error, :workers_active} = Scheduling.update(saved.version, 2, 0)

    assert {:error, _} =
             Repo.query(
               "UPDATE delivery_settings SET max_parallel_tasks=2,version=version+1 WHERE id=1"
             )

    restart(c.opts)
    assert {:ok, ^saved} = Scheduling.get()

    assert_raise RuntimeError, "Refusing to discard live scheduling evidence", fn ->
      Ecto.Migrator.down(Repo, 20_261_027_060_000, Boss.Repo.Migrations.AddDeliveryScheduling,
        log: false
      )
    end
  end

  test "racing first writes elect one durable claimant and restart never erases it", c do
    [a, b | _] = Enum.map(Enum.take(c.tasks, 2), &planned(c.project, &1))
    results = race(c.repo, [a, b], &implement/1)
    assert Enum.count(results, &match?({:ok, %Step{}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :scope_conflict}, &1)) == 1
    claimant = Enum.find([a, b], fn data -> length(Deliveries.steps(data.delivery.id)) == 2 end)
    waiting = Enum.find([a, b], &(&1 != claimant))
    assert Scheduling.blockers(waiting.delivery) == [claimant.delivery.id]
    restart(c.opts)
    assert Scheduling.blockers(waiting.delivery) == [claimant.delivery.id]
    assert {:error, :scope_conflict} = implement(waiting)
    assert {:ok, interrupted} = Deliveries.reconcile()
    assert length(interrupted) == 2
    assert Enum.all?(interrupted, &(&1.cleanup == "unknown"))
    task = Enum.at(c.tasks, 2)
    assert {:error, :busy} = Deliveries.admit(c.project.id, task.id, Ecto.UUID.generate(), "true")

    assert_raise RuntimeError, "Refusing to discard typed scope history", fn ->
      Ecto.Migrator.down(Repo, 20_261_027_060_000, Boss.Repo.Migrations.AddDeliveryScheduling,
        log: false
      )
    end
  end

  test "completed receipts cannot release Manager capacity before the actual owners exit", c do
    owner = self()

    worker = fn delivery, _repo, manager ->
      send(owner, {:started, delivery.id, self()})

      receive do
        :finish ->
          result = Deliveries.complete(delivery.id, "cancelled")
          send(manager, {:delivery_finished, delivery.id, self(), result})

          receive do
            :exit -> :ok
          end
      end
    end

    manager =
      start_supervised!(
        {Manager,
         [name: nil, repo: c.repo, registry: Boss.SchedulingTestActive, delivery_worker: worker]}
      )

    assert {:ok, %{max_parallel_tasks: 3, version: 1}} = Scheduling.set(0, 3, manager)

    for task <- Enum.take(c.tasks, 3) do
      assert {:ok, _} =
               Deliveries.start(c.project.id, task.id, Ecto.UUID.generate(), "true", manager)
    end

    pids =
      for _ <- 1..3 do
        assert_receive {:started, _, pid}
        send(pid, :finish)
        pid
      end

    eventually(fn -> map_size(:sys.get_state(manager).finished) == 3 end)
    assert {:error, :workers_active} = Scheduling.set(1, 2, manager)
    assert {:ok, %{max_parallel_tasks: 3, version: 1}} = Scheduling.get()
    for pid <- pids, do: send(pid, :exit)
    eventually(fn -> :sys.get_state(manager).active == %{} end)
    assert {:ok, %{max_parallel_tasks: 1, version: 2}} = Scheduling.set(1, 1, manager)
  end

  test "empty migration down and up restores default capacity guards", c do
    assert {:ok, _} = Scheduling.update(0, 1, 0)

    assert_raise RuntimeError, "Refusing to discard configured worker capacity", fn ->
      Ecto.Migrator.down(Repo, 20_261_027_060_000, Boss.Repo.Migrations.AddDeliveryScheduling,
        log: false
      )
    end

    assert {:ok, _} = Scheduling.update(1, 2, 0)

    assert :ok =
             Ecto.Migrator.down(
               Repo,
               20_261_027_060_000,
               Boss.Repo.Migrations.AddDeliveryScheduling,
               log: false
             )

    assert {:error, _} = Repo.query("SELECT * FROM delivery_settings")

    assert :ok =
             Ecto.Migrator.up(
               Repo,
               20_261_027_060_000,
               Boss.Repo.Migrations.AddDeliveryScheduling,
               log: false
             )

    assert {:ok, %{max_parallel_tasks: 2, version: 0}} = Scheduling.get()

    results =
      race(c.repo, c.tasks, fn task ->
        Deliveries.admit(c.project.id, task.id, Ecto.UUID.generate(), "true")
      end)

    assert Enum.count(results, &match?({:ok, {:new, _}}, &1)) == 2
    assert Enum.count(results, &match?({:error, :busy}, &1)) == 2
  end

  defp restart(opts) do
    :ok = stop_supervised(Repo)
    repo = start_supervised!({Repo, opts})
    Repo.put_dynamic_repo(repo)
    repo
  end

  defp planned(project, task) do
    {:ok, {:new, d}} = Deliveries.admit(project.id, task.id, Ecto.UUID.generate(), "true")

    intent = %{
      "run_id" => d.id,
      "project_id" => to_string(project.id),
      "repo_path" => project.root_path,
      "git_common_dir" => project.git_common_dir,
      "base_branch" => "main",
      "base_commit" => @base
    }

    {:ok, d} = Deliveries.set_intent(d.id, intent)
    {:ok, plan} = Deliveries.begin_step(d.id, "plan", 0, %{"workspace" => intent})

    report = %{
      "summary" => "Plan",
      "steps" => ["Implement"],
      "acceptance" => ["Pass"],
      "file_scopes" => [%{"path" => "lib", "kind" => "directory"}]
    }

    {:ok, plan} =
      Deliveries.finish_step(plan.id, %{
        "status" => "finished",
        "cleanup" => "group_empty",
        "exit_kind" => "exit",
        "exit_code" => 0,
        "eof" => %{"stdout" => true, "stderr" => true},
        "report" => report
      })

    %{delivery: d, plan: plan}
  end

  defp implement(data),
    do: Deliveries.begin_step(data.delivery.id, "implement", 1, %{"plan_step_id" => data.plan.id})

  defp race(repo, items, fun),
    do:
      items
      |> Enum.map(fn item ->
        Task.async(fn ->
          Repo.put_dynamic_repo(repo)
          fun.(item)
        end)
      end)
      |> Enum.map(&Task.await(&1, 5_000))

  defp eventually(fun, n \\ 150)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, n),
    do:
      if(fun.(),
        do: :ok,
        else:
          (
            Process.sleep(10)
            eventually(fun, n - 1)
          )
      )
end
