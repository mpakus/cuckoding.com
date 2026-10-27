defmodule Boss.ReviewPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Projects, Repo, Runs}
  alias Boss.Agents.Workspace
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
    {20_261_027_030_000, Boss.Repo.Migrations.PinDeliveryReviewer}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-reviews-#{Ecto.UUID.generate()}")
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
    File.cp!(Path.expand("../fixtures/check_command.py", __DIR__), Path.join(source, "check.py"))

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
        name: "Checks",
        root_path: source,
        git_common_dir: Path.join(source, ".git"),
        specs_path: source,
        base_branch: "main"
      })

    {:ok, record} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        title: "One",
        original_text: "# One"
      })

    {:ok, {:new, parent}} = Runs.admit(project.id, record.task.id, Ecto.UUID.generate())
    {:ok, intent} = Workspace.plan(project, parent.id)
    {:ok, _} = Workspace.prepare(intent)
    File.write!(Path.join(intent.path, "result.txt"), "candidate")

    {:ok, parent} =
      Runs.update(parent.id,
        workspace: Map.new(intent, fn {k, v} -> {to_string(k), v} end),
        status: "finished",
        cleanup: "group_empty"
      )

    bin = Path.join(root, "bin")
    File.mkdir!(bin)
    File.cp!(Path.expand("../fixtures/codex_review.py", __DIR__), Path.join(bin, "codex"))
    File.chmod!(Path.join(bin, "codex"), 0o700)
    previous = Map.take(System.get_env(), ["PATH", "BOSS_REVIEW_MODE", "BOSS_REVIEW_MARKER"])
    System.put_env("PATH", bin <> ":" <> System.fetch_env!("PATH"))
    System.delete_env("BOSS_REVIEW_MODE")
    System.put_env("BOSS_REVIEW_MARKER", Path.join(root, "started"))

    on_exit(fn ->
      for key <- ["PATH", "BOSS_REVIEW_MODE", "BOSS_REVIEW_MARKER"] do
        if Map.has_key?(previous, key),
          do: System.put_env(key, previous[key]),
          else: System.delete_env(key)
      end
    end)

    %{
      root: root,
      repo: repo,
      opts: opts,
      project: project,
      task: record.task,
      parent: parent,
      source: source
    }
  end

  test "actual reviewer persists only the structured assessment and survives restart/replay",
       ctx do
    check = candidate(ctx)
    manager = start_manager(ctx.repo)
    command = Ecto.UUID.generate()
    {:ok, run} = Runs.start_review(ctx.project.id, check.id, command, manager)
    saved = await_run(ctx, run.id)
    assert saved.status == "finished", inspect(saved.reason)
    assert saved.review_report["verdict"] == "approved"
    assert saved.candidate_commit == check.candidate_commit
    assert saved.config_hash == check.config_hash
    assert saved.exit_code == 0 and saved.cleanup == "group_empty"
    refute inspect(saved) =~ "SECRET_"
    assert Repo.get!(Boss.Tasks.Task, ctx.task.id).state == "new"
    assert File.read!(Path.join(ctx.source, "result.txt")) == "base"
    assert File.read!(Path.join(ctx.parent.workspace["path"], "result.txt")) == "candidate"
    assert :ok == Candidate.verify(check.workspace, check.candidate_commit)
    refute File.exists?(marker(ctx)["output"])
    :ok = stop_supervised(Manager)
    :ok = stop_supervised(Repo)
    repo = start_repo(ctx.opts)
    Repo.put_dynamic_repo(repo)
    manager = start_manager(repo)
    assert Runs.get(ctx.project.id, run.id) == saved
    assert {:ok, ^saved} = Runs.start_review(ctx.project.id, check.id, command, manager)
  end

  test "rejections are valid reports but invalid/missing output and nonzero exit never are",
       ctx do
    check = candidate(ctx)
    manager = start_manager(ctx.repo)

    for mode <- ~w(changes_requested needs_spec_revision duplicate missing oversize symlink fail) do
      System.put_env("BOSS_REVIEW_MODE", mode)
      {:ok, run} = Runs.start_review(ctx.project.id, check.id, Ecto.UUID.generate(), manager)
      saved = await_run(ctx, run.id)

      if mode in ~w(changes_requested needs_spec_revision) do
        assert saved.status == "finished", inspect({mode, saved.reason})
        assert saved.review_report["verdict"] == mode
      else
        assert saved.status == "failed", inspect({mode, saved.status, saved.reason})
        assert saved.review_report == %{}
      end

      assert saved.cleanup == "group_empty"
      refute File.exists?(marker(ctx)["output"])
      wait_idle(manager)
    end
  end

  test "candidate drift before launch prevents CLI and drift after exit prevents assessment",
       ctx do
    check = candidate(ctx)
    File.write!(Path.join(check.workspace["path"], "result.txt"), "external edit")
    manager = start_manager(ctx.repo)
    {:ok, run} = Runs.start_review(ctx.project.id, check.id, Ecto.UUID.generate(), manager)
    saved = await_run(ctx, run.id)
    assert saved.status == "failed" and saved.review_report == %{}
    refute File.exists?(Path.join(ctx.root, "started"))
    wait_idle(manager)

    for mode <- ~w(dirty head) do
      check = candidate(ctx)
      System.put_env("BOSS_REVIEW_MODE", mode)
      {:ok, run} = Runs.start_review(ctx.project.id, check.id, Ecto.UUID.generate(), manager)
      saved = await_run(ctx, run.id)
      assert saved.status == "failed" and saved.review_report == %{}, inspect(saved.reason)
      assert saved.exit_code == 0 and saved.cleanup == "group_empty"
      assert File.read!(Path.join(ctx.parent.workspace["path"], "result.txt")) == "candidate"
      wait_idle(manager)
    end
  end

  test "Stop reaches review without waiting on Manager and removes temporary report", ctx do
    check = candidate(ctx)
    manager = start_manager(ctx.repo)
    System.put_env("BOSS_REVIEW_MODE", "wait")
    {:ok, run} = Runs.start_review(ctx.project.id, check.id, Ecto.UUID.generate(), manager)
    eventually(fn -> File.exists?(Path.join(ctx.root, "started")) end)
    started = marker(ctx)
    :sys.suspend(manager)

    try do
      assert :ok = Runs.stop(ctx.project.id, run.id, Boss.ReviewTestsActive)
      eventually(fn -> dead?(started["pid"]) end)
    after
      :sys.resume(manager)
    end

    saved = await_run(ctx, run.id)
    assert saved.status == "cancelled" and saved.cleanup == "group_empty"
    assert saved.review_report == %{}
    refute File.exists?(started["output"])
  end

  test "Repo loss kills reviewer; restart quarantines without reusing PID or rerunning", ctx do
    check = candidate(ctx)
    manager = start_manager(ctx.repo)
    ref = Process.monitor(manager)
    command = Ecto.UUID.generate()
    System.put_env("BOSS_REVIEW_MODE", "late_output")
    {:ok, run} = Runs.start_review(ctx.project.id, check.id, command, manager)
    eventually(fn -> File.exists?(Path.join(ctx.root, "started")) end)
    started = marker(ctx)
    Process.exit(ctx.repo, :kill)
    assert_receive {:DOWN, ^ref, :process, ^manager, :run_storage_lost}, 3_000
    eventually(fn -> dead?(started["pid"]) end)
    assert File.read!(Path.join(ctx.root, "started.late")) == "attempted"
    directory = Path.dirname(started["output"])

    eventually(fn ->
      not File.exists?(directory) and not File.exists?(directory <> ".closing")
    end)

    repo = start_repo(ctx.opts)
    Repo.put_dynamic_repo(repo)
    manager = start_manager(repo)
    saved = Runs.get(ctx.project.id, run.id)
    assert saved.status == "interrupted" and saved.cleanup == "unknown"
    assert saved.review_report == %{} and saved.candidate_commit == check.candidate_commit
    assert {:ok, ^saved} = Runs.start_review(ctx.project.id, check.id, command, manager)

    assert {:error, :busy} =
             Runs.start_review(ctx.project.id, check.id, Ecto.UUID.generate(), manager)
  end

  test "additive review migration preserves old receipts and refuses to discard reviews", ctx do
    check = candidate(ctx)
    version = 20_261_026_160_000
    module = Boss.Repo.Migrations.AddManualReviews
    assert :ok = Ecto.Migrator.down(Repo, version, module, log: false)
    assert [[2]] = Repo.query!("SELECT COUNT(*) FROM agent_runs").rows
    assert :ok = Ecto.Migrator.up(Repo, version, module, log: false)
    assert Runs.get(ctx.project.id, check.id).candidate_commit == check.candidate_commit
    {:ok, {:new, review}} = Runs.admit_review(ctx.project.id, check.id, Ecto.UUID.generate())

    assert_raise RuntimeError, ~r/Refusing to discard review history/, fn ->
      Ecto.Migrator.down(Repo, version, module, log: false)
    end

    assert Runs.get(ctx.project.id, review.id).parent_run_id == check.id
  end

  test "lost launch intent receipt prevents the reviewer process and quarantines", ctx do
    check = candidate(ctx)

    Repo.query!(
      "CREATE TRIGGER fixture_block_review_launch BEFORE UPDATE ON agent_runs WHEN NEW.adapter='review' AND NEW.status='launching' BEGIN SELECT RAISE(ABORT, 'fixture'); END"
    )

    manager = start_manager(ctx.repo)
    {:ok, run} = Runs.start_review(ctx.project.id, check.id, Ecto.UUID.generate(), manager)
    saved = await_run(ctx, run.id)
    assert saved.status == "interrupted" and saved.cleanup == "unknown"
    assert saved.review_report == %{}
    refute File.exists?(Path.join(ctx.root, "started"))

    assert {:error, :busy} =
             Runs.start_review(ctx.project.id, check.id, Ecto.UUID.generate(), manager)
  end

  defp candidate(ctx) do
    {:ok, {:new, run}} =
      Runs.admit_check(
        ctx.project.id,
        ctx.parent.id,
        Ecto.UUID.generate(),
        "python3 check.py pass"
      )

    {:ok, intent} = Candidate.plan(ctx.parent.workspace, run.id)
    {:ok, saved} = Candidate.prepare(intent)

    {:ok, check} =
      Runs.update(run.id,
        status: "finished",
        cleanup: "group_empty",
        exit_kind: "exit",
        exit_code: 0,
        candidate_commit: saved.candidate_commit,
        workspace: intent
      )

    check
  end

  defp marker(ctx), do: ctx.root |> Path.join("started") |> File.read!() |> JSON.decode!()

  defp dead?(pid) do
    case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "stat="]) do
      {_, 1} -> true
      {status, 0} -> String.contains?(status, "Z")
    end
  end

  defp start_repo(opts),
    do: start_supervised!(Supervisor.child_spec({Repo, opts}, restart: :temporary))

  defp start_manager(repo),
    do:
      start_supervised!(
        Supervisor.child_spec(
          {Manager, [name: nil, registry: Boss.ReviewTestsActive, repo: repo]},
          restart: :temporary
        )
      )

  defp await_run(ctx, id) do
    eventually(fn -> not Runs.active?(Runs.get(ctx.project.id, id)) end)
    Runs.get(ctx.project.id, id)
  end

  defp wait_idle(manager), do: eventually(fn -> :sys.get_state(manager).active == nil end)
  defp eventually(predicate, left \\ 500)
  defp eventually(_, 0), do: flunk("Review did not settle within fixture deadline")

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
