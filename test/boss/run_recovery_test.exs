defmodule Boss.RunRecoveryTest do
  use ExUnit.Case, async: false
  alias Boss.{Projects, Repo, Runs}
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

  test "Repo loss kills a real run group and restart quarantines its committed attempt" do
    root = Path.join(System.tmp_dir!(), "boss-recovery-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, lock} = Boss.DataDirectory.acquire(root)
    on_exit(fn -> Boss.DataDirectory.release(lock) end)
    prepare_cli(root)

    opts = [
      name: nil,
      database: Path.join(root, "boss.db"),
      pool: DBConnection.ConnectionPool,
      pool_size: 2
    ]

    repo = start_repo(opts)
    Repo.put_dynamic_repo(repo)
    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)
    source = Path.join(root, "repository")
    File.mkdir!(source)
    {physical, 0} = System.cmd("/bin/pwd", ["-P"], cd: source)
    source = String.trim(physical)

    for args <- [
          ["init", "-b", "main"],
          ["config", "user.name", "Fixture"],
          ["config", "user.email", "fixture@example.invalid"],
          ["commit", "--allow-empty", "-m", "base"]
        ] do
      assert {_, 0} =
               System.cmd("git", args,
                 cd: source,
                 stderr_to_stdout: true,
                 env: [{"GIT_CONFIG_NOSYSTEM", "1"}, {"GIT_CONFIG_GLOBAL", "/dev/null"}]
               )
    end

    File.write!(Path.join(source, "user.txt"), "preserve local edits")

    project =
      Repo.insert!(%Projects.Project{
        name: "Recovery",
        root_path: source,
        git_common_dir: Path.join(source, ".git"),
        specs_path: source,
        base_branch: "main"
      })

    {:ok, record} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        original_text: "# Saved recovery task",
        title: "Recovery"
      })

    manager = start_manager(repo)
    command = Ecto.UUID.generate()
    assert {:ok, run} = Runs.start(project.id, record.task.id, command, manager)
    marker = Path.join(root, "processes.json")
    eventually(fn -> File.exists?(marker) end)
    pids = marker |> File.read!() |> JSON.decode!()
    on_exit(fn -> cleanup_fixture(pids, root) end)
    assert Enum.all?(pids, fn {_, pid} -> alive?(pid) end)
    {_, worker} = :sys.get_state(manager).active
    worker_ref = Process.monitor(worker)
    manager_ref = Process.monitor(manager)
    before_loss = Runs.get(project.id, run.id)
    retained = Path.join(before_loss.workspace["path"], "result.txt")
    assert File.read!(retained) == "retained fixture change"
    assert before_loss.spec_revision_id == record.task.spec_revision_id
    assert before_loss.workspace["base_commit"] =~ ~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/

    Process.exit(repo, :kill)
    assert_receive {:DOWN, ^manager_ref, :process, ^manager, :run_storage_lost}, 3_000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _}, 3_000
    eventually(fn -> Enum.all?(pids, fn {_, pid} -> not alive?(pid) end) end)

    replacement = start_repo(opts)
    Repo.put_dynamic_repo(replacement)
    restarted_manager = start_manager(replacement)
    recovered = Runs.get(project.id, run.id)
    assert recovered.status == "interrupted"
    assert recovered.cleanup == "unknown"
    assert recovered.workspace == before_loss.workspace
    assert recovered.spec_revision_id == before_loss.spec_revision_id
    assert recovered.finished_at
    assert File.read!(retained) == "retained fixture change"
    assert File.read!(Path.join(source, "user.txt")) == "preserve local edits"
    refute File.exists?(Path.join(source, "result.txt"))
    assert Repo.get!(Boss.Tasks.Task, record.task.id).state == "new"

    assert {:ok, ^recovered} = Runs.start(project.id, record.task.id, command, restarted_manager)

    assert {:error, :busy} =
             Runs.start(project.id, record.task.id, Ecto.UUID.generate(), restarted_manager)

    assert :sys.get_state(restarted_manager).active == nil
    assert Repo.aggregate(Runs.Run, :count) == 1
    assert File.read!(Path.join(root, "launches")) == "launch\n"
  end

  defp start_repo(opts),
    do: start_supervised!(Supervisor.child_spec({Repo, opts}, restart: :temporary))

  defp start_manager(repo),
    do:
      start_supervised!(
        Supervisor.child_spec(
          {Manager, [name: nil, registry: Boss.RecoveryRunsActive, repo: repo]},
          restart: :temporary
        )
      )

  defp prepare_cli(root) do
    old_path = System.get_env("PATH")
    old_data = Application.fetch_env!(:boss, :data_dir)
    bin = Path.join(root, "bin")
    File.mkdir!(bin)
    File.mkdir!(Path.join(root, "run-data"))

    File.write!(Path.join(bin, "codex"), """
    #!/usr/bin/env python3
    import json, os, signal, sys, time
    from pathlib import Path
    root = Path(#{JSON.encode!(root)})
    signal.alarm(15)
    assert "--sandbox" in sys.argv and "workspace-write" in sys.argv
    assert sys.argv[-1] == "-"
    sys.stdin.read()
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    child = os.fork()
    if child == 0:
        signal.alarm(15)
        while True:
            time.sleep(0.1)
    Path("result.txt").write_text("retained fixture change")
    with (root / "launches").open("a") as log:
        log.write("launch\\n")
    (root / "processes.tmp").write_text(json.dumps({"leader": os.getpid(), "child": child, "guardian": os.getppid()}))
    (root / "processes.tmp").rename(root / "processes.json")
    print(json.dumps({"type": "turn.started"}), flush=True)
    while True:
        time.sleep(0.1)
    """)

    File.chmod!(Path.join(bin, "codex"), 0o700)
    System.put_env("PATH", bin <> ":" <> old_path)
    Application.put_env(:boss, :data_dir, Path.join(root, "run-data"))

    on_exit(fn ->
      System.put_env("PATH", old_path)
      Application.put_env(:boss, :data_dir, old_data)
    end)
  end

  defp alive?(pid) do
    case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "stat="], stderr_to_stdout: true) do
      {status, 0} -> not String.contains?(status, "Z")
      _ -> false
    end
  end

  defp cleanup_fixture(pids, root) do
    for {_, pid} <- pids do
      {command, _} =
        System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "command="], stderr_to_stdout: true)

      if String.contains?(command, Path.join(root, "bin/codex")),
        do: System.cmd("/bin/kill", ["-KILL", to_string(pid)], stderr_to_stdout: true)
    end
  end

  defp eventually(predicate, remaining \\ 200)
  defp eventually(_, 0), do: flunk("Expected bounded run recovery did not occur")

  defp eventually(predicate, remaining) do
    if predicate.(),
      do: :ok,
      else:
        (
          Process.sleep(20)
          eventually(predicate, remaining - 1)
        )
  end
end
