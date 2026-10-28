defmodule Boss.DeliveryWorkerTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo, Tasks}
  alias Boss.Checks.Candidate
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
    {20_261_027_040_000, Boss.Repo.Migrations.AddWorkflowQueue},
    {20_261_027_050_000, Boss.Repo.Migrations.AddMergeIntegrationEvidence},
    {20_261_027_060_000, Boss.Repo.Migrations.AddDeliveryScheduling},
    {20_261_027_070_000, Boss.Repo.Migrations.AddAutopilot}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-delivery-#{Ecto.UUID.generate()}")
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
    File.cp!(Path.expand("../fixtures/claude_review.py", __DIR__), Path.join(bin, "claude"))
    File.chmod!(Path.join(bin, "claude"), 0o700)
    keys = ["PATH", "BOSS_DELIVERY_MODE", "BOSS_DELIVERY_FIXTURE", "BOSS_CLAUDE_MODE"]
    previous = Map.take(System.get_env(), keys)
    System.put_env("PATH", bin <> ":" <> System.fetch_env!("PATH"))
    System.delete_env("BOSS_DELIVERY_MODE")
    System.delete_env("BOSS_CLAUDE_MODE")
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

  test "complete plan, implementation, check and review are durable without raw output", ctx do
    manager = start_manager(ctx.repo)
    command = Ecto.UUID.generate()
    {:ok, run} = start(ctx, manager, command)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "ready_to_merge", inspect({saved, Deliveries.steps(run.id)})
    steps = Deliveries.steps(run.id)
    assert Enum.map(steps, & &1.kind) == ~w(plan implement snapshot check review)
    assert Enum.all?(steps, &(&1.status == "finished"))
    assert List.last(steps).receipt["report"]["verdict"] == "approved"
    assert Repo.get!(Tasks.Task, ctx.task.id).state == "ready_to_merge"
    assert Repo.aggregate(Boss.Runs.Run, :count) == 0
    assert File.read!(Path.join(ctx.source, "result.txt")) == "base"
    assert_no_raw(steps)
    :ok = stop_supervised(Manager)
    :ok = stop_supervised(Repo)
    repo = start_repo(ctx.opts)
    Repo.put_dynamic_repo(repo)
    manager = start_manager(repo)
    assert Deliveries.get(ctx.project.id, run.id) == saved
    assert {:ok, ^saved} = start(ctx, manager, command)
    assert length(calls(ctx)) == 3
  end

  test "Claude reviews complete supplied evidence and cannot finish the task on CLI success",
       ctx do
    manager = start_manager(ctx.repo)
    command = Ecto.UUID.generate()
    {:ok, run} = start_claude(ctx, manager, command)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    assert saved.reviewer == "claude"
    assert Enum.map(calls(ctx), & &1["kind"]) == ~w(plan implement claude_review)
    review = List.last(steps)
    assert review.receipt["report"]["verdict"] == "approved"
    assert review.receipt["summary"]["usage"]["input_tokens"] == 12
    assert Repo.get!(Tasks.Task, ctx.task.id).state == "ready_to_merge"
    assert File.read!(Path.join(ctx.source, "result.txt")) == "base"
    [claude] = Enum.filter(calls(ctx), &(&1["kind"] == "claude_review"))
    refute File.exists?(claude["cwd"])
    assert_no_raw(steps)
    assert {:ok, ^saved} = start_claude(ctx, manager, command)
    assert {:error, :idempotency_conflict} = start(ctx, manager, command)
    assert length(calls(ctx)) == 3
  end

  test "missing selected Claude fails before any Codex work or workspace preparation", ctx do
    bin = Path.join(ctx.root, "bin")
    File.rename!(Path.join(bin, "claude"), Path.join(bin, "claude-disabled"))
    System.put_env("PATH", bin <> ":/usr/bin:/bin")
    assert is_nil(System.find_executable("claude"))
    manager = start_manager(ctx.repo)
    {:ok, run} = start_claude(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "failed" and saved.reason =~ "Claude is unavailable"
    assert saved.intent == %{}
    assert Deliveries.steps(run.id) == []
    refute File.exists?(Path.join(ctx.root, "calls"))
  end

  test "Claude rejection feeds Codex fix and another fresh Claude review", ctx do
    System.put_env("BOSS_CLAUDE_MODE", "reject_once")
    manager = start_manager(ctx.repo)
    {:ok, run} = start_claude(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    assert saved.cycle == 2

    assert Enum.map(calls(ctx), & &1["kind"]) ==
             ~w(plan implement claude_review implement claude_review)

    [first, second] = Enum.filter(steps, &(&1.kind == "review"))
    assert first.receipt["report"]["verdict"] == "changes_requested"
    assert second.receipt["report"]["verdict"] == "approved"
    assert first.input["candidate_commit"] != second.input["candidate_commit"]
    assert first.input["original_base"] == second.input["original_base"]
    assert_no_raw(steps)
  end

  for mode <-
        ~w(malformed oversized unsafe_init external_tool denied error missing_report coverage duplicate truncated nonzero refusal aborted) do
    @claude_mode mode
    test "Claude #{@claude_mode} halts without fallback or automatic repair", ctx do
      System.put_env("BOSS_CLAUDE_MODE", @claude_mode)
      manager = start_manager(ctx.repo)
      {:ok, run} = start_claude(ctx, manager)
      saved = await_delivery(ctx, run.id)
      assert saved.status == "failed", inspect({saved, Deliveries.steps(run.id)})
      assert Enum.map(calls(ctx), & &1["kind"]) == ~w(plan implement claude_review)
      assert List.last(Deliveries.steps(run.id)).status == "failed"
      assert_no_raw(Deliveries.steps(run.id))
    end
  end

  test "Stop reaches Claude directly while Manager is suspended", ctx do
    System.put_env("BOSS_CLAUDE_MODE", "wait")
    manager = start_manager(ctx.repo)
    {:ok, run} = start_claude(ctx, manager)
    eventually(fn -> File.exists?(Path.join(ctx.root, "claude-waiting")) end)
    :sys.suspend(manager)

    try do
      assert :ok = Deliveries.stop(ctx.project.id, run.id, Boss.DeliveryTestsActive)
      eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, run.id)) end)
    after
      :sys.resume(manager)
    end

    saved = await_delivery(ctx, run.id)
    assert saved.status == "cancelled" and saved.cleanup == "group_empty"
    assert Enum.map(calls(ctx), & &1["kind"]) == ~w(plan implement claude_review)
    refute Map.has_key?(List.last(Deliveries.steps(run.id)).receipt, "report")
  end

  test "review rejection fixes a new worktree from the rejected candidate with full-base review",
       ctx do
    System.put_env("BOSS_DELIVERY_MODE", "reject_once")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    assert saved.cycle == 2
    [first, second] = Enum.filter(steps, &(&1.kind == "snapshot"))
    [_, fix] = Enum.filter(steps, &(&1.kind == "implement"))
    assert fix.input["workspace"]["base_commit"] == first.receipt["candidate_commit"]
    refute first.receipt["workspace"]["path"] == second.receipt["workspace"]["path"]

    assert File.read!(Path.join(first.receipt["workspace"]["path"], "result.txt")) ==
             "candidate-1\n"

    assert File.read!(Path.join(second.receipt["workspace"]["path"], "result.txt")) ==
             "candidate-2\n"

    assert :ok == Candidate.verify(first.receipt["workspace"], first.receipt["candidate_commit"])

    assert :ok ==
             Candidate.verify(second.receipt["workspace"], second.receipt["candidate_commit"])

    assert_no_raw(steps)
  end

  test "complete check failure consumes a cycle and provides full output to the fix", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "check_once")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})

    assert Enum.map(steps, & &1.kind) ==
             ~w(plan implement snapshot check implement snapshot check review)

    failed = Enum.find(steps, &(&1.kind == "check"))
    assert failed.status == "failed" and failed.receipt["output_complete"]
    assert failed.receipt["exit_code"] == 3
    assert_no_raw(steps)
  end

  test "repeated unchanged feedback stops before the three-cycle maximum", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "repeated")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "blocked", inspect(saved)
    assert saved.cycle == 2
    assert saved.reason =~ "same failure"
    assert length(Enum.filter(calls(ctx), &(&1["kind"] == "implement"))) == 2
  end

  test "different rejected trees still stop after three total cycles", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "reject_always")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "blocked", inspect(saved)
    assert saved.cycle == 3
    assert saved.reason =~ "budget"
    assert length(Enum.filter(calls(ctx), &(&1["kind"] == "implement"))) == 3
  end

  test "repeated complete check failure stops on the unchanged tree despite fresh commit IDs",
       ctx do
    System.put_env("BOSS_DELIVERY_MODE", "check_repeated")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "blocked", inspect(saved)
    assert saved.cycle == 2 and saved.reason =~ "same failure"
    assert Enum.count(calls(ctx), &(&1["kind"] == "implement")) == 2
    refute Enum.any?(calls(ctx), &(&1["kind"] == "review"))
  end

  for mode <- ~w(plan_dirty plan_invalid coverage check_invalid_utf8 check_dirty) do
    @mode mode
    test "#{mode} halts without automatic repair", ctx do
      System.put_env("BOSS_DELIVERY_MODE", @mode)
      manager = start_manager(ctx.repo)
      {:ok, run} = start(ctx, manager)
      saved = await_delivery(ctx, run.id)
      assert saved.status == "failed", inspect(saved)

      if @mode in ~w(plan_dirty check_dirty),
        do: assert(saved.reason =~ "files, HEAD or retained ref changed")

      assert length(Enum.filter(calls(ctx), &(&1["kind"] == "implement"))) <= 1
      assert_no_raw(Deliveries.steps(run.id))
    end
  end

  test "unclear specification requests input without modifying the pinned source", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "needs_spec")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "needs_input", inspect(saved)

    assert Repo.get!(Projects.SpecRevision, saved.spec_revision_id).original_text ==
             "# One\nCreate result.txt"
  end

  test "Stop reaches implementation while the Manager is suspended and starts no later stage",
       ctx do
    System.put_env("BOSS_DELIVERY_MODE", "wait")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    eventually(fn -> File.exists?(Path.join(ctx.root, "waiting")) end)
    :sys.suspend(manager)

    try do
      assert :ok = Deliveries.stop(ctx.project.id, run.id, Boss.DeliveryTestsActive)
      eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, run.id)) end)
    after
      :sys.resume(manager)
    end

    saved = await_delivery(ctx, run.id)
    assert saved.status == "cancelled" and saved.cleanup == "group_empty"
    assert Enum.map(Deliveries.steps(run.id), & &1.kind) == ~w(plan implement)
  end

  test "lost implementation intent prevents the effect and quarantines delivery", ctx do
    Repo.query!(
      "CREATE TRIGGER fixture_stop_implement BEFORE INSERT ON delivery_steps WHEN NEW.kind='implement' BEGIN SELECT RAISE(ABORT, 'fixture'); END"
    )

    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "interrupted" and saved.cleanup == "unknown"
    assert Enum.map(calls(ctx), & &1["kind"]) == ["plan"]
    assert {:error, :busy} = start(ctx, manager)
  end

  test "Repo loss interrupts delivery and replay never respawns the abandoned worker", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "wait")
    manager = start_manager(ctx.repo)
    monitor = Process.monitor(manager)
    command = Ecto.UUID.generate()
    {:ok, run} = start(ctx, manager, command)
    eventually(fn -> File.exists?(Path.join(ctx.root, "waiting")) end)
    pid = ctx.root |> Path.join("waiting") |> File.read!() |> String.to_integer()
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
    saved = Deliveries.get(ctx.project.id, run.id)
    assert saved.status == "interrupted" and saved.cleanup == "unknown"
    assert {:ok, ^saved} = start(ctx, manager, command)
    assert {:error, :busy} = start(ctx, manager)
    assert Enum.map(calls(ctx), & &1["kind"]) == ~w(plan implement)
  end

  defp start(ctx, manager, command \\ Ecto.UUID.generate()),
    do: Deliveries.start(ctx.project.id, ctx.task.id, command, "python3 check.py", manager)

  defp start_claude(ctx, manager, command \\ Ecto.UUID.generate()),
    do:
      Deliveries.start(
        ctx.project.id,
        ctx.task.id,
        command,
        "python3 check.py",
        "claude",
        manager
      )

  defp assert_no_raw(steps), do: refute(inspect(steps, limit: :infinity) =~ "SECRET_SENTINEL")

  defp calls(ctx),
    do:
      ctx.root
      |> Path.join("calls")
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

  defp start_repo(opts),
    do: start_supervised!(Supervisor.child_spec({Repo, opts}, restart: :temporary))

  defp start_manager(repo),
    do:
      start_supervised!(
        Supervisor.child_spec(
          {Manager, [name: nil, registry: Boss.DeliveryTestsActive, repo: repo]},
          restart: :temporary
        )
      )

  defp await_delivery(ctx, id) do
    eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, id)) end)
    Deliveries.get(ctx.project.id, id)
  end

  defp eventually(predicate, left \\ 1500)
  defp eventually(_, 0), do: flunk("Delivery did not settle within fixture deadline")

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
