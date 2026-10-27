defmodule Boss.DeliveryIntegrationWorkerTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo, Tasks}
  alias Boss.Runs.Manager
  @moduletag skip: :os.type() != {:unix, :darwin}
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
    {20_261_027_040_000, Boss.Repo.Migrations.AddWorkflowQueue}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-delivery-integration-#{Ecto.UUID.generate()}")
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

    File.write!(
      Path.join(source, "check.py"),
      """
      import json
      import time
      root = Path(os.environ["BOSS_DELIVERY_FIXTURE"])
      with (root / "check-calls").open("a") as calls:
          calls.write(json.dumps(str(Path.cwd())) + "\\n")
      if os.environ.get("BOSS_POST_CHECK_MODE") == "fail":
          sys.exit(3)
      if os.environ.get("BOSS_POST_CHECK_MODE") == "wait":
          (root / "post-wait").write_text(str(os.getpid()))
          while True:
              time.sleep(0.05)
      """,
      [:append]
    )

    for args <- [
          ["init", "-b", "main"],
          ["config", "user.name", "Fixture"],
          ["config", "user.email", "fixture@example.invalid"],
          ["add", "."],
          ["commit", "-m", "base"]
        ] do
      assert {_, 0} =
               System.cmd("git", args,
                 cd: source,
                 stderr_to_stdout: true,
                 env: [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}]
               )
    end

    project =
      Repo.insert!(%Projects.Project{
        name: "Delivery",
        root_path: source,
        git_common_dir: Path.join(source, ".git"),
        specs_path: source,
        base_branch: "main"
      })

    {:ok, record} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        title: "One",
        original_text: "# One\nCreate result.txt"
      })

    bin = Path.join(root, "bin")
    File.mkdir!(bin)
    File.cp!(Path.expand("../fixtures/codex_delivery.py", __DIR__), Path.join(bin, "codex"))
    File.chmod!(Path.join(bin, "codex"), 0o700)
    keys = ["PATH", "BOSS_DELIVERY_MODE", "BOSS_DELIVERY_FIXTURE", "BOSS_POST_CHECK_MODE"]
    previous = Map.take(System.get_env(), keys)
    System.put_env("PATH", bin <> ":" <> System.fetch_env!("PATH"))
    System.delete_env("BOSS_DELIVERY_MODE")
    System.delete_env("BOSS_POST_CHECK_MODE")
    System.put_env("BOSS_DELIVERY_FIXTURE", root)

    on_exit(fn ->
      for key <- keys do
        if Map.has_key?(previous, key),
          do: System.put_env(key, previous[key]),
          else: System.delete_env(key)
      end
    end)

    %{root: root, repo: repo, opts: opts, project: project, task: record.task, source: source}
  end

  test "approved candidate publishes, passes post-checks and frees target before Done", ctx do
    {manager, delivery, start_command} = ready(ctx)
    candidate = candidate(delivery)
    command = Ecto.UUID.generate()
    assert {:ok, _} = Deliveries.integrate(ctx.project.id, delivery.id, command, manager)
    saved = await_delivery(ctx, delivery.id)
    assert saved.status == "done", inspect({saved, Deliveries.steps(delivery.id)})
    assert saved.cleanup == "group_empty"
    assert Repo.get!(Tasks.Task, ctx.task.id).state == "done"
    assert git(ctx.source, ["rev-parse", "main"]) == candidate
    assert File.read!(Path.join(ctx.source, "result.txt")) == "base"

    assert File.read!(Path.join(saved.integration_intent["path"], "result.txt")) ==
             "candidate-1\n"

    assert {_, 1} =
             System.cmd("git", ["symbolic-ref", "-q", "HEAD"],
               cd: saved.integration_intent["path"]
             )

    git(ctx.source, ["switch", "main"])
    assert File.read!(Path.join(ctx.source, "result.txt")) == "candidate-1\n"

    assert Enum.map(Deliveries.steps(delivery.id), & &1.kind) ==
             ~w(plan implement snapshot check review publish post_check)

    assert calls(ctx, "check-calls") |> length() == 2
    assert calls(ctx, "calls") |> length() == 3
    refute inspect(Deliveries.steps(delivery.id), limit: :infinity) =~ "SECRET_SENTINEL"
    wait_idle(manager)

    assert {:ok, ^saved} =
             Deliveries.start(
               ctx.project.id,
               ctx.task.id,
               start_command,
               "python3 check.py",
               manager
             )

    assert {:ok, ^saved} = Deliveries.integrate(ctx.project.id, delivery.id, command, manager)
    assert calls(ctx, "check-calls") |> length() == 2
    assert calls(ctx, "calls") |> length() == 3
  end

  test "a user's checked-out target prevents publication and Done", ctx do
    {manager, delivery, _} = ready(ctx, false)
    base = git(ctx.source, ["rev-parse", "main"])

    assert {:ok, _} =
             Deliveries.integrate(ctx.project.id, delivery.id, Ecto.UUID.generate(), manager)

    saved = await_delivery(ctx, delivery.id)
    assert saved.status == "blocked", inspect(saved)
    assert saved.reason =~ "checked out"
    assert git(ctx.source, ["rev-parse", "main"]) == base
    assert calls(ctx, "check-calls") |> length() == 1
    refute Repo.get!(Tasks.Task, ctx.task.id).state == "done"
  end

  test "changed target invalidates old approval without moving the user's branch", ctx do
    {manager, delivery, _} = ready(ctx, false)
    git(ctx.source, ["commit", "--allow-empty", "-m", "user commit"])
    changed = git(ctx.source, ["rev-parse", "main"])
    git(ctx.source, ["switch", "--detach"])

    assert {:ok, _} =
             Deliveries.integrate(ctx.project.id, delivery.id, Ecto.UUID.generate(), manager)

    saved = await_delivery(ctx, delivery.id)
    assert saved.status == "blocked", inspect(saved)
    assert saved.reason =~ "changed"
    assert git(ctx.source, ["rev-parse", "main"]) == changed
    assert calls(ctx, "check-calls") |> length() == 1
    refute Repo.get!(Tasks.Task, ctx.task.id).state == "done"
  end

  test "failed post-check keeps publication and blocks Done without rollback", ctx do
    {manager, delivery, _} = ready(ctx)
    System.put_env("BOSS_POST_CHECK_MODE", "fail")

    assert {:ok, _} =
             Deliveries.integrate(ctx.project.id, delivery.id, Ecto.UUID.generate(), manager)

    saved = await_delivery(ctx, delivery.id)
    assert saved.status == "blocked", inspect(saved)
    assert saved.reason =~ "not rolled back"
    assert git(ctx.source, ["rev-parse", "main"]) == candidate(delivery)
    post = List.last(Deliveries.steps(delivery.id))
    assert post.kind == "post_check" and post.status == "failed"
    assert post.receipt["exit_code"] == 3 and post.receipt["output_complete"]
    refute Repo.get!(Tasks.Task, ctx.task.id).state == "done"
  end

  test "Stop reaches a post-check with Manager suspended and retains published evidence", ctx do
    {manager, delivery, _} = ready(ctx)
    System.put_env("BOSS_POST_CHECK_MODE", "wait")

    assert {:ok, _} =
             Deliveries.integrate(ctx.project.id, delivery.id, Ecto.UUID.generate(), manager)

    eventually(fn -> File.exists?(Path.join(ctx.root, "post-wait")) end)
    :sys.suspend(manager)

    try do
      assert :ok =
               Deliveries.stop(ctx.project.id, delivery.id, Boss.DeliveryIntegrationTestsActive)

      eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, delivery.id)) end)
    after
      :sys.resume(manager)
    end

    saved = await_delivery(ctx, delivery.id)
    assert saved.status == "blocked" and saved.cleanup == "group_empty"
    assert List.last(Deliveries.steps(delivery.id)).status == "cancelled"
    assert git(ctx.source, ["rev-parse", "main"]) == candidate(delivery)
    refute Repo.get!(Tasks.Task, ctx.task.id).state == "done"
  end

  test "lost publication receipt quarantines a possibly published target and never reruns", ctx do
    {manager, delivery, _} = ready(ctx)

    Repo.query!(
      "CREATE TRIGGER fixture_lose_publish BEFORE UPDATE ON delivery_steps WHEN OLD.kind='publish' AND NEW.status='finished' BEGIN SELECT RAISE(ABORT, 'fixture'); END"
    )

    command = Ecto.UUID.generate()
    assert {:ok, _} = Deliveries.integrate(ctx.project.id, delivery.id, command, manager)
    saved = await_delivery(ctx, delivery.id)
    assert saved.status == "interrupted" and saved.cleanup == "unknown"
    assert git(ctx.source, ["rev-parse", "main"]) == candidate(delivery)
    assert List.last(Deliveries.steps(delivery.id)).status == "interrupted"
    assert calls(ctx, "check-calls") |> length() == 1
    wait_idle(manager)
    assert {:ok, ^saved} = Deliveries.integrate(ctx.project.id, delivery.id, command, manager)
    assert calls(ctx, "check-calls") |> length() == 1
    refute Repo.get!(Tasks.Task, ctx.task.id).state == "done"
  end

  test "Repo loss after publication kills the check and restart quarantines without replay",
       ctx do
    {manager, delivery, _} = ready(ctx)
    System.put_env("BOSS_POST_CHECK_MODE", "wait")
    monitor = Process.monitor(manager)
    command = Ecto.UUID.generate()
    assert {:ok, _} = Deliveries.integrate(ctx.project.id, delivery.id, command, manager)
    eventually(fn -> File.exists?(Path.join(ctx.root, "post-wait")) end)
    pid = ctx.root |> Path.join("post-wait") |> File.read!() |> String.to_integer()
    Process.exit(ctx.repo, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^manager, :run_storage_lost}, 3_000

    eventually(fn ->
      case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "stat="]) do
        {_, 1} -> true
        {status, 0} -> String.contains?(status, "Z")
      end
    end)

    repo = start_repo(ctx.opts)
    Repo.put_dynamic_repo(repo)
    manager = start_manager(repo)
    saved = Deliveries.get(ctx.project.id, delivery.id)
    assert saved.status == "interrupted" and saved.cleanup == "unknown"
    assert git(ctx.source, ["rev-parse", "main"]) == candidate(delivery)
    assert {:ok, ^saved} = Deliveries.integrate(ctx.project.id, delivery.id, command, manager)
    assert calls(ctx, "check-calls") |> length() == 2
    refute Repo.get!(Tasks.Task, ctx.task.id).state == "done"
  end

  defp ready(ctx, free_target \\ true) do
    manager = start_manager(ctx.repo)
    command = Ecto.UUID.generate()

    {:ok, delivery} =
      Deliveries.start(ctx.project.id, ctx.task.id, command, "python3 check.py", manager)

    saved = await_delivery(ctx, delivery.id)
    assert saved.status == "ready_to_merge", inspect({saved, Deliveries.steps(delivery.id)})
    wait_idle(manager)
    if free_target, do: git(ctx.source, ["switch", "--detach"])
    {manager, saved, command}
  end

  defp candidate(delivery) do
    Deliveries.steps(delivery.id)
    |> Enum.find(&(&1.kind == "review"))
    |> Map.fetch!(:input)
    |> Map.fetch!("candidate_commit")
  end

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

  defp calls(ctx, name),
    do:
      ctx.root
      |> Path.join(name)
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

  defp start_repo(opts),
    do: start_supervised!(Supervisor.child_spec({Repo, opts}, restart: :temporary))

  defp start_manager(repo),
    do:
      start_supervised!(
        Supervisor.child_spec(
          {Manager, [name: nil, registry: Boss.DeliveryIntegrationTestsActive, repo: repo]},
          restart: :temporary
        )
      )

  defp await_delivery(ctx, id) do
    eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, id)) end)
    Deliveries.get(ctx.project.id, id)
  end

  defp wait_idle(manager), do: eventually(fn -> :sys.get_state(manager).active == %{} end)
  defp eventually(predicate, left \\ 2000)
  defp eventually(_, 0), do: flunk("Integration did not settle within fixture deadline")

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
