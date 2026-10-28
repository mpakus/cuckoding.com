defmodule Boss.MergeIntegrationWorkerTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo, Tasks}
  alias Boss.Runs.Manager
  alias Boss.Checks.Candidate
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
    {20_261_027_060_000, Boss.Repo.Migrations.AddDeliveryScheduling}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-merge-integration-#{Ecto.UUID.generate()}")
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
    File.cp!(Path.expand("../fixtures/claude_merge_review.py", __DIR__), Path.join(bin, "claude"))
    File.chmod!(Path.join(bin, "claude"), 0o700)
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

  for reviewer <- ~w(codex claude) do
    @tag reviewer: reviewer
    test "advanced target uses fresh #{reviewer} evidence and preserves both original approval and user checkout",
         ctx do
      {manager, delivery} = ready(ctx, ctx.reviewer)
      original = step(delivery, "review")
      original_workspace = step(delivery, "check").input["workspace"]
      original_sha = candidate(delivery)
      target = advance(ctx)
      user = preserve_checkout(ctx)
      command = Ecto.UUID.generate()
      assert {:ok, _} = Deliveries.integrate(ctx.project.id, delivery.id, command, manager)
      saved = await_delivery(ctx, delivery.id)
      assert saved.status == "done", inspect({saved, Deliveries.steps(delivery.id)})
      assert saved.reviewer == ctx.reviewer
      assert saved.cleanup == "group_empty"
      assert Repo.get!(Tasks.Task, ctx.task.id).state == "done"
      merge = step(saved, "merge")
      check = step(saved, "merge_check")
      review = step(saved, "merge_review")
      merged = merge.receipt["candidate_commit"]
      assert merged not in [target, original_sha]

      assert git(ctx.source, ["rev-list", "--parents", "-n", "1", merged]) ==
               "#{merged} #{target} #{original_sha}"

      assert git(ctx.source, ["rev-parse", "main"]) == merged
      assert saved.integration_intent["base_commit"] == target
      assert saved.integration_intent["candidate_commit"] == merged
      assert saved.integration_intent["candidate"] == merge.receipt["workspace"]
      assert merge.input["original_review_step_id"] == original.id
      assert merge.input["original_candidate"] == original_sha
      assert check.input["merge_step_id"] == merge.id
      assert review.input["merge_check_step_id"] == check.id
      assert review.input["original_review_step_id"] == original.id
      assert review.input["candidate_commit"] == merged
      assert review.input["target_commit"] == target
      assert review.receipt["report"]["verdict"] == "approved"
      assert review.receipt["cleanup"] == "group_empty"
      assert step(saved, "publish").input["review_step_id"] == review.id
      assert step(saved, "review") == original
      assert :ok = Candidate.verify(original_workspace, original_sha)

      assert :ok =
               Candidate.verify_merge(merge.receipt["workspace"], merged, target, original_sha)

      assert checkout(ctx) == user

      assert File.read!(Path.join(saved.integration_intent["path"], "parallel.txt")) ==
               "parallel task\n"

      assert File.read!(Path.join(saved.integration_intent["path"], "result.txt")) ==
               "candidate-1\n"

      assert {_, 1} =
               System.cmd("git", ["symbolic-ref", "-q", "HEAD"],
                 cd: saved.integration_intent["path"]
               )

      assert calls(ctx, "check-calls") == [
               original_workspace["path"],
               merge.receipt["workspace"]["path"],
               saved.integration_intent["path"]
             ]

      assert length(calls(ctx, "calls")) == 4
      fresh = List.last(calls(ctx, "calls"))
      assert fresh["target_commit"] == target
      assert fresh["kind"] == if(ctx.reviewer == "claude", do: "claude_review", else: "review")
      refute inspect(Deliveries.steps(delivery.id), limit: :infinity) =~ "SECRET_SENTINEL"
      wait_idle(manager)
      assert {:ok, ^saved} = Deliveries.integrate(ctx.project.id, delivery.id, command, manager)
      assert length(calls(ctx, "calls")) == 4
    end
  end

  test "conflicting target records failed merge without checks, review or publication", ctx do
    {manager, delivery} = ready(ctx)
    target = advance(ctx, "result.txt", "conflicting target\n")
    user = preserve_checkout(ctx)
    saved = integrate(ctx, manager, delivery)
    assert saved.status == "blocked" and saved.cleanup == "group_empty", inspect(saved)
    assert saved.reason =~ "conflicts"
    merge = step(saved, "merge")
    assert merge.status == "failed"
    assert merge.receipt["outcome"] == "merge_conflict"
    assert length(calls(ctx, "calls")) == 3
    assert length(calls(ctx, "check-calls")) == 1
    refute step(saved, "merge_check")
    refute step(saved, "merge_review")
    assert_unpublished(ctx, saved, target, user)
  end

  test "rewritten target history is rejected before merge effects", ctx do
    {manager, delivery} = ready(ctx)
    old = git(ctx.source, ["rev-parse", "main"])
    tree = git(ctx.source, ["rev-parse", "HEAD^{tree}"])
    target = git(ctx.source, ["commit-tree", tree, "-m", "rewritten root"])
    git(ctx.source, ["switch", "--detach", target])
    git(ctx.source, ["update-ref", "refs/heads/main", target, old])
    user = preserve_checkout(ctx)
    saved = integrate(ctx, manager, delivery)
    assert saved.status == "blocked"
    assert saved.reason =~ "no longer descends"
    refute step(saved, "merge")
    assert length(calls(ctx, "calls")) == 3
    assert length(calls(ctx, "check-calls")) == 1
    assert_unpublished(ctx, saved, target, user)
  end

  test "saved check failure stops a clean merge before fresh review", ctx do
    {manager, delivery} = ready(ctx)
    target = advance(ctx)
    user = preserve_checkout(ctx)
    System.put_env("BOSS_POST_CHECK_MODE", "fail")
    saved = integrate(ctx, manager, delivery)
    assert saved.status == "blocked" and saved.cleanup == "group_empty", inspect(saved)
    assert step(saved, "merge").status == "finished"
    check = step(saved, "merge_check")
    assert check.status == "failed"
    assert check.receipt["exit_code"] == 3
    assert check.receipt["output_complete"]
    assert length(calls(ctx, "calls")) == 3
    assert length(calls(ctx, "check-calls")) == 2
    refute step(saved, "merge_review")
    assert_unpublished(ctx, saved, target, user)
  end

  for {mode, status, verdict} <- [
        {"reject_always", "blocked", "changes_requested"},
        {"needs_spec", "needs_input", "needs_spec_revision"}
      ] do
    @tag mode: mode, status: status, verdict: verdict
    test "fresh review #{verdict} retains the merge without repair or publication", ctx do
      {manager, delivery} = ready(ctx)
      original = step(delivery, "review")
      target = advance(ctx)
      user = preserve_checkout(ctx)
      System.put_env("BOSS_DELIVERY_MODE", ctx.mode)
      saved = integrate(ctx, manager, delivery)
      assert saved.status == ctx.status and saved.cleanup == "group_empty", inspect(saved)
      assert step(saved, "review") == original
      review = step(saved, "merge_review")
      assert review.status == "finished"
      assert review.receipt["report"]["verdict"] == ctx.verdict
      merge = step(saved, "merge")

      assert :ok =
               Candidate.verify_merge(
                 merge.receipt["workspace"],
                 merge.receipt["candidate_commit"],
                 target,
                 candidate(delivery)
               )

      assert length(calls(ctx, "check-calls")) == 2
      assert length(calls(ctx, "calls")) == 4
      assert Enum.count(calls(ctx, "calls"), &(&1["kind"] == "implement")) == 1
      assert_unpublished(ctx, saved, target, user)
    end
  end

  test "a second target advance during fresh review retains stale evidence without publishing",
       ctx do
    {manager, delivery, _target, user, command, pid} = waiting_review(ctx)
    target = git(ctx.source, ["rev-parse", "main"])
    tree = git(ctx.source, ["rev-parse", "#{target}^{tree}"])
    changed = git(ctx.source, ["commit-tree", tree, "-p", target, "-m", "advanced during review"])
    git(ctx.source, ["update-ref", "refs/heads/main", changed, target])
    File.write!(Path.join(ctx.root, "integration-review-release"), "continue")
    saved = await_delivery(ctx, delivery.id)
    assert saved.status == "blocked" and saved.cleanup == "group_empty", inspect(saved)
    assert step(saved, "merge_review").status == "failed"
    assert step(saved, "merge").input["target_commit"] == target
    assert_unpublished(ctx, saved, changed, user)
    process_gone(pid)
    wait_idle(manager)
    assert {:ok, ^saved} = Deliveries.integrate(ctx.project.id, delivery.id, command, manager)
    assert length(calls(ctx, "calls")) == 4
  end

  test "Stop reaches fresh merge review while Manager is suspended and retains the unpublished candidate",
       ctx do
    {manager, delivery, target, user, command, pid} = waiting_review(ctx)
    :sys.suspend(manager)

    try do
      assert :ok = Deliveries.stop(ctx.project.id, delivery.id, Boss.MergeIntegrationTestsActive)
      eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, delivery.id)) end)
    after
      :sys.resume(manager)
    end

    saved = await_delivery(ctx, delivery.id)
    assert saved.status == "cancelled" and saved.cleanup == "group_empty", inspect(saved)
    assert step(saved, "merge_review").status == "cancelled"
    assert_unpublished(ctx, saved, target, user)
    process_gone(pid)
    wait_idle(manager)
    assert {:ok, ^saved} = Deliveries.integrate(ctx.project.id, delivery.id, command, manager)
    assert length(calls(ctx, "calls")) == 4
  end

  test "Repo loss during fresh review kills the process and restart quarantines without a new invocation",
       ctx do
    {manager, delivery, target, user, command, pid} = waiting_review(ctx)
    original = step(delivery, "review")
    monitor = Process.monitor(manager)
    Process.exit(ctx.repo, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^manager, :run_storage_lost}, 3_000
    process_gone(pid)
    repo = start_repo(ctx.opts)
    Repo.put_dynamic_repo(repo)
    manager = start_manager(repo)
    saved = Deliveries.get(ctx.project.id, delivery.id)
    assert saved.status == "interrupted" and saved.cleanup == "unknown", inspect(saved)
    assert step(saved, "merge_review").status == "interrupted"
    assert step(saved, "review") == original
    assert_unpublished(ctx, saved, target, user)
    assert {:ok, ^saved} = Deliveries.integrate(ctx.project.id, delivery.id, command, manager)

    {:ok, next} =
      Projects.record_spec(ctx.project.id, %{
        relative_path: "next.md",
        title: "Next",
        original_text: "# Next"
      })

    assert {:error, :busy} =
             Deliveries.start(
               ctx.project.id,
               next.task.id,
               Ecto.UUID.generate(),
               "python3 check.py",
               manager
             )

    assert length(calls(ctx, "calls")) == 4
    assert length(calls(ctx, "check-calls")) == 2
    assert :sys.get_state(manager).active == %{}
  end

  defp ready(ctx, reviewer \\ "codex") do
    manager = start_manager(ctx.repo)

    {:ok, delivery} =
      Deliveries.start(
        ctx.project.id,
        ctx.task.id,
        Ecto.UUID.generate(),
        "python3 check.py",
        reviewer,
        manager
      )

    saved = await_delivery(ctx, delivery.id)
    assert saved.status == "ready_to_merge", inspect({saved, Deliveries.steps(delivery.id)})
    wait_idle(manager)
    {manager, saved}
  end

  defp advance(ctx, file \\ "parallel.txt", contents \\ "parallel task\n") do
    File.write!(Path.join(ctx.source, file), contents)
    git(ctx.source, ["add", file])
    git(ctx.source, ["commit", "-m", "parallel target change"])
    target = git(ctx.source, ["rev-parse", "main"])
    git(ctx.source, ["switch", "--detach"])
    target
  end

  defp preserve_checkout(ctx) do
    File.write!(Path.join(ctx.source, "user-staged.txt"), "preserve staged user file")
    git(ctx.source, ["add", "user-staged.txt"])
    File.write!(Path.join(ctx.source, "user-untracked.txt"), "preserve untracked user file")
    checkout(ctx)
  end

  defp checkout(ctx) do
    index = git(ctx.source, ["rev-parse", "--git-path", "index"]) |> Path.expand(ctx.source)

    %{
      head: git(ctx.source, ["rev-parse", "HEAD"]),
      index: File.read!(index),
      result: File.read!(Path.join(ctx.source, "result.txt")),
      staged: File.read!(Path.join(ctx.source, "user-staged.txt")),
      untracked: File.read!(Path.join(ctx.source, "user-untracked.txt"))
    }
  end

  defp integrate(ctx, manager, delivery) do
    assert {:ok, _} =
             Deliveries.integrate(ctx.project.id, delivery.id, Ecto.UUID.generate(), manager)

    await_delivery(ctx, delivery.id)
  end

  defp assert_unpublished(ctx, saved, target, user) do
    assert git(ctx.source, ["rev-parse", "main"]) == target
    assert saved.integration_intent == %{}
    refute step(saved, "publish")
    refute Repo.get!(Tasks.Task, ctx.task.id).state == "done"
    assert checkout(ctx) == user
    original = step(saved, "check").input["workspace"]
    assert :ok = Candidate.verify(original, candidate(saved))
  end

  defp waiting_review(ctx) do
    {manager, delivery} = ready(ctx)
    target = advance(ctx)
    user = preserve_checkout(ctx)
    System.put_env("BOSS_DELIVERY_MODE", "integration_wait")
    command = Ecto.UUID.generate()
    assert {:ok, _} = Deliveries.integrate(ctx.project.id, delivery.id, command, manager)
    marker = Path.join(ctx.root, "integration-review-wait")
    eventually(fn -> File.exists?(marker) end)
    assert step(delivery, "merge_review").status == "running"
    pid = marker |> File.read!() |> String.to_integer()
    {manager, delivery, target, user, command, pid}
  end

  defp step(delivery, kind), do: Enum.find(Deliveries.steps(delivery.id), &(&1.kind == kind))

  defp process_gone(pid) do
    eventually(fn ->
      case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "stat="]) do
        {_, 1} -> true
        {status, 0} -> String.contains?(status, "Z")
      end
    end)
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
          {Manager, [name: nil, registry: Boss.MergeIntegrationTestsActive, repo: repo]},
          restart: :temporary
        )
      )

  defp await_delivery(ctx, id) do
    eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, id)) end)
    Deliveries.get(ctx.project.id, id)
  end

  defp wait_idle(manager), do: eventually(fn -> :sys.get_state(manager).active == %{} end)
  defp eventually(predicate, left \\ 2000)
  defp eventually(_, 0), do: flunk("Merge integration did not settle within fixture deadline")

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
