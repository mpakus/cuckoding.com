defmodule Boss.CheckPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Projects, Repo, Runs}
  alias Boss.Agents.Workspace
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
    root = Path.join(System.tmp_dir!(), "boss-checks-#{Ecto.UUID.generate()}")
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

  test "passing checks retain immutable candidate/config across Repo restart without touching source",
       ctx do
    manager = start_manager(ctx.repo)
    command = Ecto.UUID.generate()

    {:ok, check} =
      Runs.start_check(ctx.project.id, ctx.parent.id, command, "python3 check.py pass", manager)

    saved = await_run(ctx, check.id, &(!Runs.active?(&1)))
    assert saved.status == "finished", inspect({saved.status, saved.reason})
    assert saved.exit_code == 0 and saved.cleanup == "group_empty"
    assert saved.candidate_commit =~ ~r/\A[0-9a-f]{40,64}\z/
    assert saved.parent_run_id == ctx.parent.id
    assert saved.spec_revision_id == ctx.task.spec_revision_id
    assert File.read!(Path.join(saved.workspace["path"], "result.txt")) == "candidate"
    assert File.read!(Path.join(ctx.parent.workspace["path"], "result.txt")) == "candidate"
    assert File.read!(Path.join(ctx.source, "result.txt")) == "base"
    refute inspect(saved.summary) =~ "SECRET_"
    assert saved.summary["stdout_bytes"] > 0
    assert Repo.get!(Boss.Tasks.Task, ctx.task.id).state == "new"
    :ok = stop_supervised(Manager)
    :ok = stop_supervised(Repo)
    repo = start_repo(ctx.opts)
    Repo.put_dynamic_repo(repo)
    manager = start_manager(repo)
    assert Runs.get(ctx.project.id, check.id) == saved

    assert {:ok, ^saved} =
             Runs.start_check(
               ctx.project.id,
               ctx.parent.id,
               command,
               "python3 check.py pass",
               manager
             )
  end

  test "nonzero exit and zero-exit dirty or moved candidates never pass", ctx do
    manager = start_manager(ctx.repo)

    for mode <- ~w(fail tracked untracked head) do
      {:ok, check} =
        Runs.start_check(
          ctx.project.id,
          ctx.parent.id,
          Ecto.UUID.generate(),
          "python3 check.py #{mode}",
          manager
        )

      saved = await_run(ctx, check.id, &(!Runs.active?(&1)))
      assert saved.status == "failed", inspect({mode, saved.status, saved.reason})
      assert saved.exit_code == if(mode == "fail", do: 7, else: 0)
      assert saved.cleanup == "group_empty"
      assert File.read!(Path.join(ctx.parent.workspace["path"], "result.txt")) == "candidate"
      wait_idle(manager)
    end
  end

  test "Stop bypasses suspended Manager and retains check candidate", ctx do
    manager = start_manager(ctx.repo)
    marker = Path.join(ctx.root, "started")

    {:ok, check} =
      Runs.start_check(
        ctx.project.id,
        ctx.parent.id,
        Ecto.UUID.generate(),
        ~s(python3 check.py wait "#{marker}"),
        manager
      )

    eventually(fn -> File.exists?(marker) end)
    :sys.suspend(manager)

    try do
      assert :ok = Runs.stop(ctx.project.id, check.id, Boss.CheckTestsActive)

      eventually(fn ->
        pid = marker |> File.read!() |> String.to_integer()

        case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "stat="]) do
          {_, 1} -> true
          {status, 0} -> String.contains?(status, "Z")
        end
      end)
    after
      :sys.resume(manager)
    end

    saved = await_run(ctx, check.id, &(!Runs.active?(&1)))
    assert saved.status == "cancelled" and saved.cleanup == "group_empty"
    assert File.exists?(saved.workspace["path"])
  end

  test "candidate persistence failure prevents command execution and quarantines the retained copy",
       ctx do
    Repo.query!(
      "CREATE TRIGGER fixture_block_candidate BEFORE UPDATE ON agent_runs WHEN NEW.candidate_commit IS NOT NULL BEGIN SELECT RAISE(ABORT, 'fixture'); END"
    )

    manager = start_manager(ctx.repo)
    marker = Path.join(ctx.root, "must-not-start")

    {:ok, check} =
      Runs.start_check(
        ctx.project.id,
        ctx.parent.id,
        Ecto.UUID.generate(),
        ~s(python3 check.py wait "#{marker}"),
        manager
      )

    saved = await_run(ctx, check.id, &(!Runs.active?(&1)))
    assert saved.status == "interrupted" and saved.cleanup == "unknown"
    assert File.exists?(saved.workspace["path"])
    refute File.exists?(marker)

    assert {:error, :busy} =
             Runs.start_check(
               ctx.project.id,
               ctx.parent.id,
               Ecto.UUID.generate(),
               "python3 check.py pass",
               manager
             )
  end

  test "Repo loss interrupts a running check and restart never executes its command again", ctx do
    manager = start_manager(ctx.repo)
    ref = Process.monitor(manager)
    marker = Path.join(ctx.root, "repo-loss-check")
    command = Ecto.UUID.generate()
    text = ~s(python3 check.py wait "#{marker}")
    {:ok, check} = Runs.start_check(ctx.project.id, ctx.parent.id, command, text, manager)
    eventually(fn -> File.exists?(marker) end)
    pid = marker |> File.read!() |> String.to_integer()
    before_loss = Runs.get(ctx.project.id, check.id)
    Process.exit(ctx.repo, :kill)
    assert_receive {:DOWN, ^ref, :process, ^manager, :run_storage_lost}, 3_000

    eventually(fn ->
      case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "stat="]) do
        {_, 1} -> true
        {status, 0} -> String.contains?(status, "Z")
      end
    end)

    replacement = start_repo(ctx.opts)
    Repo.put_dynamic_repo(replacement)
    restarted = start_manager(replacement)
    saved = Runs.get(ctx.project.id, check.id)
    assert saved.status == "interrupted" and saved.cleanup == "unknown"
    assert saved.candidate_commit == before_loss.candidate_commit
    assert saved.check_config == before_loss.check_config

    assert {:ok, ^saved} =
             Runs.start_check(ctx.project.id, ctx.parent.id, command, text, restarted)

    assert {:error, :busy} =
             Runs.start_check(
               ctx.project.id,
               ctx.parent.id,
               Ecto.UUID.generate(),
               text,
               restarted
             )

    assert Repo.aggregate(Runs.Run, :count) == 2
  end

  test "check migration preserves old runs on empty rollback and refuses to discard check history",
       ctx do
    assert :ok =
             Ecto.Migrator.down(Repo, 20_261_026_160_000, Boss.Repo.Migrations.AddManualReviews,
               log: false
             )

    version = 20_261_026_060_000
    module = Boss.Repo.Migrations.AddManualChecks
    assert :ok = Ecto.Migrator.down(Repo, version, module, log: false)
    assert [[1]] = Repo.query!("SELECT COUNT(*) FROM agent_runs").rows
    assert :ok = Ecto.Migrator.up(Repo, version, module, log: false)

    assert :ok =
             Ecto.Migrator.up(Repo, 20_261_026_160_000, Boss.Repo.Migrations.AddManualReviews,
               log: false
             )

    assert Runs.get(ctx.project.id, ctx.parent.id).parent_run_id == nil

    {:ok, {:new, check}} =
      Runs.admit_check(ctx.project.id, ctx.parent.id, Ecto.UUID.generate(), "true")

    assert_raise RuntimeError, ~r/Refusing to discard check history/, fn ->
      Ecto.Migrator.down(Repo, version, module, log: false)
    end

    assert Runs.get(ctx.project.id, check.id).check_config["argv"] == ["true"]
  end

  defp start_repo(opts),
    do: start_supervised!(Supervisor.child_spec({Repo, opts}, restart: :temporary))

  defp start_manager(repo),
    do:
      start_supervised!(
        Supervisor.child_spec({Manager, [name: nil, registry: Boss.CheckTestsActive, repo: repo]},
          restart: :temporary
        )
      )

  defp await_run(ctx, id, predicate) do
    eventually(fn -> predicate.(Runs.get(ctx.project.id, id)) end)
    Runs.get(ctx.project.id, id)
  end

  defp wait_idle(manager), do: eventually(fn -> :sys.get_state(manager).active == nil end)
  defp eventually(predicate, left \\ 500)
  defp eventually(_, 0), do: flunk("Check did not settle within its fixture deadline")

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
