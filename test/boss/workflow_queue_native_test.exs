defmodule Boss.WorkflowQueueNativeTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo, Tasks}
  alias Boss.Deliveries.{Queue, Scheduling}
  alias Boss.Runs.Manager
  @moduletag skip: :os.type() != {:unix, :darwin}
  @moduletag capture_log: true
  @moduletag timeout: 120_000
  @registry Boss.WorkflowQueueNativeActive
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
    root = Path.join(System.tmp_dir!(), "boss-queue-native-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, lock} = Boss.DataDirectory.acquire(root)
    on_exit(fn -> Boss.DataDirectory.release(lock) end)
    old_data = Application.fetch_env!(:boss, :data_dir)
    Application.put_env(:boss, :data_dir, root)
    on_exit(fn -> Application.put_env(:boss, :data_dir, old_data) end)

    opts = [
      name: nil,
      database: Path.join(root, "boss.db"),
      pool: DBConnection.ConnectionPool,
      pool_size: 2
    ]

    repo = start_repo(opts)
    Repo.put_dynamic_repo(repo)
    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)
    source = Path.join(root, "source")
    File.mkdir!(source)
    {physical, 0} = System.cmd("/bin/pwd", ["-P"], cd: source)
    source = String.trim(physical)
    File.write!(Path.join(source, "result.txt"), "base")
    File.cp!(Path.expand("../fixtures/delivery_check.py", __DIR__), Path.join(source, "check.py"))

    for args <- [
          ["init", "-b", "main"],
          ["config", "user.name", "Fixture"],
          ["config", "user.email", "fixture@example.invalid"],
          ["add", "."],
          ["commit", "-m", "base"]
        ],
        do: git(source, args)

    project =
      Repo.insert!(%Projects.Project{
        name: "Native queue",
        root_path: source,
        git_common_dir: Path.join(source, ".git"),
        specs_path: source,
        base_branch: "main"
      })

    tasks =
      for name <- ~w(one two three) do
        {:ok, record} =
          Projects.record_spec(project.id, %{
            relative_path: "#{name}.md",
            explicit_id: name,
            title: name,
            original_text: "---\nid: #{name}\n---\n# #{name}\nCreate result.txt"
          })

        record.task
      end

    gates = Path.join(root, "gates")
    bin = Path.join(root, "bin")
    File.mkdir!(gates)
    File.mkdir!(bin)
    File.cp!(Path.expand("../fixtures/codex_queue.py", __DIR__), Path.join(bin, "codex"))
    File.chmod!(Path.join(bin, "codex"), 0o700)

    env = %{
      "PATH" => bin <> ":" <> System.fetch_env!("PATH"),
      "BOSS_QUEUE_GATES" => gates,
      "BOSS_QUEUE_CODEX_FIXTURE" => Path.expand("../fixtures/codex_delivery.py", __DIR__),
      "BOSS_DELIVERY_FIXTURE" => root,
      "BOSS_DELIVERY_MODE" => "approved"
    }

    previous = Map.take(System.get_env(), Map.keys(env))
    System.put_env(env)

    on_exit(fn ->
      for key <- Map.keys(env) do
        if Map.has_key?(previous, key),
          do: System.put_env(key, previous[key]),
          else: System.delete_env(key)
      end
    end)

    %{
      root: root,
      gates: gates,
      repo: repo,
      opts: opts,
      source: source,
      project: project,
      tasks: tasks
    }
  end

  test "two native workers own distinct worktrees; Stop frees only its slot and old approval cannot publish",
       ctx do
    manager = start_manager(ctx.repo)
    [one, two] = enqueue(%{ctx | tasks: Enum.take(ctx.tasks, 2)}, manager)
    first = waiting(ctx, one)
    second = waiting(ctx, two)
    [three] = enqueue(%{ctx | tasks: Enum.drop(ctx.tasks, 2)}, manager)

    {:ok, record} =
      Projects.record_spec(ctx.project.id, %{
        relative_path: "dependent.md",
        explicit_id: "dependent",
        title: "Dependent",
        original_text:
          "---\nid: dependent\ndepends_on: [two]\n---\n# Dependent\nCreate result.txt"
      })

    {:ok, dependent} =
      Queue.enqueue(
        ctx.project.id,
        record.task.id,
        Ecto.UUID.generate(),
        "python3 check.py",
        "codex",
        manager
      )

    assert implementation_path(first) != implementation_path(second)
    assert first.intent["base_commit"] == second.intent["base_commit"]
    assert map_size(:sys.get_state(manager).active) == 2
    assert request(ctx, three).status == "queued"
    assert request(ctx, three).delivery_id == nil
    assert alive?(pid(ctx, first)) and alive?(pid(ctx, second))

    assert :ok = Deliveries.stop(ctx.project.id, first.id, @registry)
    cancelled = terminal(ctx, first.id)
    assert cancelled.status == "cancelled" and cancelled.cleanup == "group_empty"
    eventually(fn -> not alive?(pid(ctx, first)) end)
    assert alive?(pid(ctx, second))
    assert Deliveries.get(ctx.project.id, second.id).status == "implementing"

    third = waiting(ctx, three)

    assert implementation_path(third) not in [
             implementation_path(first),
             implementation_path(second)
           ]

    assert map_size(:sys.get_state(manager).active) == 2
    release(ctx, second)
    release(ctx, third)

    for delivery <- [second, third] do
      saved = terminal(ctx, delivery.id)
      assert saved.status == "ready_to_merge", inspect({saved, Deliveries.steps(saved.id)})
      assert saved.cleanup == "group_empty"
    end

    eventually(fn -> :sys.get_state(manager).active == %{} end)
    assert request(ctx, dependent).status == "queued"
    assert request(ctx, dependent).delivery_id == nil
    assert File.read!(Path.join(ctx.source, "result.txt")) == "base"
    refute File.exists?(Path.join(ctx.source, "first-only.txt"))
    git(ctx.source, ["switch", "--detach"])

    assert {:ok, _} =
             Deliveries.integrate(ctx.project.id, second.id, Ecto.UUID.generate(), manager)

    assert terminal(ctx, second.id).status == "done"
    unlocked = waiting(ctx, dependent)
    assert Repo.get!(Tasks.Task, second.task_id).state == "done"
    assert :ok = Deliveries.stop(ctx.project.id, unlocked.id, @registry)
    assert terminal(ctx, unlocked.id).status == "cancelled"
    eventually(fn -> :sys.get_state(manager).active == %{} end)
    published = git(ctx.source, ["rev-parse", "main"])

    assert {:ok, _} =
             Deliveries.integrate(ctx.project.id, third.id, Ecto.UUID.generate(), manager)

    integrated = terminal(ctx, third.id)
    assert integrated.status == "done", inspect({integrated, Deliveries.steps(third.id)})
    steps = Deliveries.steps(third.id)
    original = Enum.find(steps, &(&1.kind == "review"))
    merged = Enum.find(steps, &(&1.kind == "merge"))
    fresh_review = Enum.find(steps, &(&1.kind == "merge_review"))
    assert fresh_review.receipt["report"]["verdict"] == "approved"
    assert fresh_review.input["original_review_step_id"] == original.id
    assert integrated.integration_intent["base_commit"] == published
    sha = integrated.integration_intent["candidate_commit"]
    assert sha == merged.receipt["candidate_commit"]
    assert git(ctx.source, ["rev-parse", "main"]) == sha

    assert git(ctx.source, ["rev-list", "--parents", "-n", "1", sha]) ==
             "#{sha} #{published} #{original.input["candidate_commit"]}"

    assert Repo.get!(Tasks.Task, third.task_id).state == "done"
    assert File.read!(Path.join(ctx.source, "result.txt")) == "base"
  end

  test "Repo loss kills both native workers, pauses the queue and quarantines saved attempts",
       ctx do
    manager = start_manager(ctx.repo)
    [one, two] = enqueue(%{ctx | tasks: Enum.take(ctx.tasks, 2)}, manager)
    first = waiting(ctx, one)
    second = waiting(ctx, two)
    [three] = enqueue(%{ctx | tasks: Enum.drop(ctx.tasks, 2)}, manager)
    pids = Enum.map([first, second], &pid(ctx, &1))
    assert Enum.all?(pids, &alive?/1)
    monitor = Process.monitor(manager)
    stop_supervised!(Repo)
    assert_receive {:DOWN, ^monitor, :process, ^manager, _}, 5_000
    eventually(fn -> Enum.all?(pids, &(not alive?(&1))) end)

    repo = start_repo(ctx.opts)
    Repo.put_dynamic_repo(repo)
    manager = start_manager(repo)

    for delivery <- [first, second] do
      saved = Deliveries.get(ctx.project.id, delivery.id)
      assert saved.status == "interrupted" and saved.cleanup == "unknown"
      refute Repo.get!(Tasks.Task, saved.task_id).state == "done"
    end

    saved = request(ctx, three)
    assert saved.status == "paused" and saved.delivery_id == nil
    assert :sys.get_state(manager).active == %{}
    assert {:ok, _} = Queue.resume(ctx.project.id, saved.id, manager)
    # Observe an actual scheduler sweep; a synchronous call alone can overtake
    # the zero-delay timer and would not prove that quarantine blocked dispatch.
    eventually(fn -> :sys.get_state(manager).queue_cursor == saved.id end)
    assert request(ctx, three).delivery_id == nil
    assert :sys.get_state(manager).active == %{}
    assert length(File.ls!(ctx.gates)) == 2
  end

  test "overlap waits before writes without churn; Stop bypasses a suspended Manager", ctx do
    predict(ctx, %{"one" => scope("src"), "two" => scope("SRC/file.ex")})
    manager = start_manager(ctx.repo)
    [one] = enqueue(%{ctx | tasks: Enum.take(ctx.tasks, 1)}, manager)
    first = waiting(ctx, one)
    [two] = enqueue(%{ctx | tasks: Enum.slice(ctx.tasks, 1, 1)}, manager)
    second = planned(ctx, two)
    assert implementation_path(second) == nil
    before = Deliveries.steps(second.id)
    Process.sleep(1_100)
    assert Deliveries.steps(second.id) == before
    assert Deliveries.get(ctx.project.id, second.id) == second
    assert length(File.ls!(ctx.gates)) == 1
    assert {:ok, %{max_parallel_tasks: 2}} = Scheduling.get()

    :ok = :sys.suspend(manager)

    try do
      assert :ok = Deliveries.stop(ctx.project.id, second.id, @registry)
      assert terminal(ctx, second.id).status == "cancelled"
      assert alive?(pid(ctx, first))
      assert implementation_path(second) == nil
    after
      :sys.resume(manager)
    end

    assert :ok = Deliveries.stop(ctx.project.id, first.id, @registry)
    assert terminal(ctx, first.id).status == "cancelled"
  end

  test "overlap releases after checks and review; one and three workers honor persisted capacity",
       ctx do
    predict(ctx, %{
      "one" => scope("src"),
      "two" => scope("src/file.ex"),
      "three" => scope("other")
    })

    manager = start_manager(ctx.repo)
    assert {:ok, settings} = Scheduling.get()
    assert {:ok, one_worker} = Scheduling.set(settings.version, 1, manager)
    [one, two, three] = enqueue(ctx, manager)
    first = waiting(ctx, one)
    assert request(ctx, two).status == "queued"
    assert request(ctx, three).status == "queued"
    assert {:ok, three_workers} = Scheduling.set(one_worker.version, 3, manager)
    second = planned(ctx, two)
    third = waiting(ctx, three)
    assert map_size(:sys.get_state(manager).active) == 3
    assert {:error, :workers_active} = Scheduling.set(three_workers.version, 1, manager)
    assert implementation_path(second) == nil
    release(ctx, first)
    assert terminal(ctx, first.id).status == "ready_to_merge"
    second = waiting(ctx, two)
    assert alive?(pid(ctx, third))
    assert first.intent["base_commit"] == second.intent["base_commit"]

    for delivery <- [second, third] do
      assert :ok = Deliveries.stop(ctx.project.id, delivery.id, @registry)
      assert terminal(ctx, delivery.id).status == "cancelled"
    end

    eventually(fn -> :sys.get_state(manager).active == %{} end)
    assert {:ok, _} = Scheduling.set(three_workers.version, 1, manager)
  end

  test "Repo loss kills a scope waiter and writer; restart never replays either", ctx do
    predict(ctx, %{"one" => scope("src"), "two" => scope("src/file.ex")})
    manager = start_manager(ctx.repo)
    [one] = enqueue(%{ctx | tasks: Enum.take(ctx.tasks, 1)}, manager)
    first = waiting(ctx, one)
    [two] = enqueue(%{ctx | tasks: Enum.slice(ctx.tasks, 1, 1)}, manager)
    second = planned(ctx, two)
    state = :sys.get_state(manager)
    {_, waiter} = state.active[second.id]
    waiter_monitor = Process.monitor(waiter)
    manager_monitor = Process.monitor(manager)
    writer_pid = pid(ctx, first)
    stop_supervised!(Repo)
    assert_receive {:DOWN, ^waiter_monitor, :process, ^waiter, _}, 5_000
    assert_receive {:DOWN, ^manager_monitor, :process, ^manager, _}, 5_000
    eventually(fn -> not alive?(writer_pid) end)
    repo = start_repo(ctx.opts)
    Repo.put_dynamic_repo(repo)
    restarted = start_manager(repo)

    for delivery <- [first, second] do
      saved = Deliveries.get(ctx.project.id, delivery.id)
      assert saved.status == "interrupted" and saved.cleanup == "unknown"
    end

    assert implementation_path(second) == nil
    assert :sys.get_state(restarted).active == %{}
    assert length(File.ls!(ctx.gates)) == 1
  end

  test "lost peer cleanup stops a scope waiter before its first write", ctx do
    predict(ctx, %{"one" => scope("src"), "two" => scope("src/file.ex")})
    manager = start_manager(ctx.repo)
    [one] = enqueue(%{ctx | tasks: Enum.take(ctx.tasks, 1)}, manager)
    peer = waiting(ctx, one)
    [two] = enqueue(%{ctx | tasks: Enum.slice(ctx.tasks, 1, 1)}, manager)
    survivor = planned(ctx, two)
    lose_owner(ctx, manager, peer)
    stopped = terminal(ctx, survivor.id)
    assert stopped.status == "failed" and stopped.cleanup == "group_empty"
    assert stopped.reason =~ "No further implementation started"
    assert implementation_path(stopped) == nil
    assert length(File.ls!(ctx.gates)) == 1
  end

  test "lost peer cleanup stops a later fix without misclassifying the survivor cleanup", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "reject_once")
    manager = start_manager(ctx.repo)
    [one, two] = enqueue(%{ctx | tasks: Enum.take(ctx.tasks, 2)}, manager)
    peer = waiting(ctx, one)
    survivor = waiting(ctx, two)
    lose_owner(ctx, manager, peer)
    release(ctx, survivor)
    stopped = terminal(ctx, survivor.id)
    assert stopped.status == "failed" and stopped.cleanup == "group_empty"
    assert stopped.reason =~ "No further implementation started"
    steps = Deliveries.steps(stopped.id)
    assert Enum.count(steps, &(&1.kind == "implement")) == 1
    review = Enum.find(steps, &(&1.kind == "review"))
    assert review.receipt["report"]["verdict"] == "changes_requested"
    eventually(fn -> not alive?(pid(ctx, survivor)) end)
    assert Deliveries.get(ctx.project.id, peer.id).cleanup == "unknown"
    assert File.read!(Path.join(ctx.source, "result.txt")) == "base"
  end

  defp lose_owner(ctx, manager, delivery) do
    {_, owner} = :sys.get_state(manager).active[delivery.id]
    native_pid = pid(ctx, delivery)
    Process.exit(owner, :kill)
    assert terminal(ctx, delivery.id).cleanup == "unknown"
    eventually(fn -> not alive?(native_pid) end)
  end

  defp scope(path), do: [%{"path" => path, "kind" => "file"}]

  defp predict(ctx, scopes),
    do: File.write!(Path.join(ctx.root, "scopes.json"), JSON.encode!(scopes))

  defp planned(ctx, request) do
    eventually(fn ->
      id = request(ctx, request).delivery_id
      id && Enum.any?(Deliveries.steps(id), &(&1.kind == "plan" and &1.status == "finished"))
    end)

    Deliveries.get(ctx.project.id, request(ctx, request).delivery_id)
  end

  defp enqueue(ctx, manager) do
    Enum.map(ctx.tasks, fn task ->
      {:ok, request} =
        Queue.enqueue(
          ctx.project.id,
          task.id,
          Ecto.UUID.generate(),
          "python3 check.py",
          "codex",
          manager
        )

      request
    end)
  end

  defp request(ctx, request),
    do: Enum.find(Queue.list(ctx.project.id, request.task_id), &(&1.id == request.id))

  defp waiting(ctx, request) do
    eventually(fn ->
      case request(ctx, request).delivery_id do
        nil ->
          false

        id ->
          delivery = Deliveries.get(ctx.project.id, id)

          assert Deliveries.active?(delivery),
                 inspect(
                   {delivery.status, delivery.reason,
                    Enum.map(Deliveries.steps(id), &{&1.kind, &1.status, &1.receipt})}
                 )

          is_binary(implementation_path(delivery)) and
            File.exists?(gate(ctx, delivery, "waiting"))
      end
    end)

    Deliveries.get(ctx.project.id, request(ctx, request).delivery_id)
  end

  defp terminal(ctx, id) do
    eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, id)) end, 3000)
    Deliveries.get(ctx.project.id, id)
  end

  defp implementation_path(delivery) do
    case Enum.find(Deliveries.steps(delivery.id), &(&1.kind == "implement")) do
      nil -> nil
      step -> step.input["workspace"]["path"]
    end
  end

  defp gate(ctx, delivery, suffix),
    do: Path.join(ctx.gates, Path.basename(implementation_path(delivery)) <> "." <> suffix)

  defp pid(ctx, delivery),
    do: ctx |> gate(delivery, "waiting") |> File.read!() |> String.to_integer()

  defp release(ctx, delivery), do: File.write!(gate(ctx, delivery, "release"), "")

  defp alive?(pid) do
    case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "stat="]) do
      {_, 1} -> false
      {status, 0} -> not String.contains?(status, "Z")
    end
  end

  defp start_repo(opts),
    do: start_supervised!(Supervisor.child_spec({Repo, opts}, restart: :temporary))

  defp start_manager(repo),
    do:
      start_supervised!(
        Supervisor.child_spec({Manager, [name: nil, registry: @registry, repo: repo]},
          restart: :temporary
        )
      )

  defp git(path, args) do
    {output, status} =
      System.cmd("git", args,
        cd: path,
        stderr_to_stdout: true,
        env: [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}]
      )

    assert status == 0, inspect({args, output})
    String.trim(output)
  end

  defp eventually(predicate, left \\ 1500)
  defp eventually(_, 0), do: flunk("Native queue did not settle within fixture deadline")

  defp eventually(predicate, left) do
    if predicate.(),
      do: :ok,
      else:
        (
          Process.sleep(20)
          eventually(predicate, left - 1)
        )
  end
end
