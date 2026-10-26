defmodule Boss.RunPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Repo, Projects, Runs}
  alias Boss.Runs.Manager

  @migrations [
    {20_261_025_180_000, Boss.Repo.Migrations.CreateProjects},
    {20_261_025_220_000, Boss.Repo.Migrations.CreateSpecRevisions},
    {20_261_025_230_000, Boss.Repo.Migrations.TrackMissingSpecs},
    {20_261_026_010_000, Boss.Repo.Migrations.CreateTaskEvents},
    {20_261_026_040_000, Boss.Repo.Migrations.CreateAgentRuns},
    {20_261_026_060_000, Boss.Repo.Migrations.AddManualChecks},
    {20_261_026_160_000, Boss.Repo.Migrations.AddManualReviews}
  ]

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-runs-db-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

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
        name: "Runs",
        root_path: root,
        git_common_dir: Path.join(root, ".git"),
        specs_path: root,
        base_branch: "main"
      })

    {:ok, record} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        original_text: "# One",
        title: "One"
      })

    %{root: root, repo: repo, repo_opts: opts, project: project, task: record.task}
  end

  test "committed intent survives restart, is quarantined, and is never respawned", ctx do
    id = Ecto.UUID.generate()
    assert {:ok, {:new, original}} = Runs.admit(ctx.project.id, ctx.task.id, id)
    :ok = stop_supervised(Repo)
    repo = start_supervised!({Repo, ctx.repo_opts})
    Repo.put_dynamic_repo(repo)
    parent = self()
    manager = start_manager(repo, fn _, _, _ -> send(parent, :unexpected_launch) end)
    saved = Runs.get(ctx.project.id, original.id)
    assert saved.status == "interrupted"
    assert saved.cleanup == "unknown"
    assert saved.spec_revision_id == ctx.task.spec_revision_id
    assert {:ok, ^saved} = Runs.start(ctx.project.id, ctx.task.id, id, manager)

    assert {:error, :busy} =
             Runs.start(ctx.project.id, ctx.task.id, Ecto.UUID.generate(), manager)

    refute_receive :unexpected_launch
  end

  test "concurrent admission creates only one durable attempt", ctx do
    results =
      1..6
      |> Task.async_stream(
        fn _ ->
          Repo.put_dynamic_repo(ctx.repo)
          Runs.admit(ctx.project.id, ctx.task.id, Ecto.UUID.generate())
        end,
        max_concurrency: 3
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, {:new, _}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :busy})) == 5
    assert Repo.aggregate(Runs.Run, :count) == 1
  end

  test "committed launch ownership survives requester death; scoped Stop bypasses suspended Manager",
       ctx do
    parent = self()

    worker = fn run, repo, manager ->
      Repo.put_dynamic_repo(repo)
      assert Runs.get(run.project_id, run.id).status == "preparing"
      send(parent, {:working, run, self()})

      receive do
        :stop ->
          send(parent, :stop_received)

          result =
            Runs.update(run.id,
              status: "cancelled",
              cleanup: "group_empty",
              finished_at: DateTime.utc_now()
            )

          send(manager, {:run_finished, run.id, result})
      end
    end

    manager = start_manager(ctx.repo, worker)
    command = Ecto.UUID.generate()

    requester =
      spawn(fn ->
        send(parent, {:admitted, Runs.start(ctx.project.id, ctx.task.id, command, manager)})
      end)

    ref = Process.monitor(requester)
    assert_receive {:admitted, {:ok, run}}
    assert_receive {:DOWN, ^ref, _, _, _}
    assert_receive {:working, ^run, owner}
    assert Process.alive?(owner)
    assert {:ok, ^run} = Runs.start(ctx.project.id, ctx.task.id, command, manager)

    assert {:error, :busy} =
             Runs.start(ctx.project.id, ctx.task.id, Ecto.UUID.generate(), manager)

    assert {:error, :not_running} = Runs.stop(ctx.project.id + 1, run.id, Boss.TestRunsActive)
    :sys.suspend(manager)

    try do
      assert :ok = Runs.stop(ctx.project.id, run.id, Boss.TestRunsActive)
      assert_receive :stop_received, 200
    after
      :sys.resume(manager)
    end
  end

  test "completed command replays while another attempt owns the worker", ctx do
    command = Ecto.UUID.generate()
    {:ok, {:new, first}} = Runs.admit(ctx.project.id, ctx.task.id, command)
    {:ok, first} = Runs.update(first.id, status: "failed", cleanup: "not_started")
    parent = self()

    manager =
      start_manager(ctx.repo, fn _, _, _ ->
        send(parent, :second_started)
        receive do: (:stop -> :ok)
      end)

    {:ok, second} = Runs.start(ctx.project.id, ctx.task.id, Ecto.UUID.generate(), manager)
    assert_receive :second_started
    assert {:ok, ^first} = Runs.start(ctx.project.id, ctx.task.id, command, manager)
    assert {:error, :invalid_command} = Runs.start(%{}, nil, [], manager)
    assert Process.alive?(manager)
    assert Repo.aggregate(Runs.Run, :count) == 2
    assert Runs.active?(Runs.get(ctx.project.id, second.id))
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "real worker and native transport implement the pinned task only in a retained worktree",
       ctx do
    prepare_cli(ctx, "finish")

    {:ok, _} =
      Projects.record_spec(ctx.project.id, %{
        relative_path: "one.md",
        original_text: "# Newer",
        title: "Newer"
      })

    manager = start_manager(ctx.repo, &Boss.Runs.Worker.execute/3)
    assert {:ok, run} = Runs.start(ctx.project.id, ctx.task.id, Ecto.UUID.generate(), manager)
    saved = wait_run(ctx.project.id, run.id, &(!Runs.active?(&1)))
    assert saved.status == "finished", inspect({saved.status, saved.reason})
    assert saved.cleanup == "group_empty"
    assert saved.exit_kind == "exit" and saved.exit_code == 0
    assert saved.os_pid > 0 and saved.started_at
    path = saved.workspace["path"]
    assert File.read!(Path.join(path, "result.txt")) == "fixture change\n"
    prompt = File.read!(Path.join(path, "received-spec.txt"))
    assert String.ends_with?(prompt, "# One")
    refute prompt =~ "# Newer"
    refute inspect(saved.summary) =~ "SECRET_"
    refute File.exists?(Path.join([ctx.root, "repository", "result.txt"]))
    assert File.read!(Path.join([ctx.root, "repository", "user.txt"])) == "local change"
    assert Repo.get!(Boss.Tasks.Task, ctx.task.id).state == "new"
    assert length(Runs.list(ctx.project.id, ctx.task.id)) == 1
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "real worker Stop cancels Codex-shaped process and retains its edits", ctx do
    prepare_cli(ctx, "wait")
    manager = start_manager(ctx.repo, &Boss.Runs.Worker.execute/3)
    {:ok, run} = Runs.start(ctx.project.id, ctx.task.id, Ecto.UUID.generate(), manager)
    started = wait_run(ctx.project.id, run.id, &(&1.status == "running"))
    wait_file(Path.join(started.workspace["path"], "result.txt"))
    assert :ok = Runs.stop(ctx.project.id, run.id, Boss.TestRunsActive)
    stopped = wait_run(ctx.project.id, run.id, &(!Runs.active?(&1)))
    assert stopped.status == "cancelled", inspect({stopped.status, stopped.reason})
    assert stopped.cleanup == "group_empty"
    assert File.exists?(Path.join(started.workspace["path"], "result.txt"))
    refute File.exists?(Path.join([ctx.root, "repository", "result.txt"]))
  end

  defp prepare_cli(ctx, mode) do
    old_path = System.get_env("PATH")
    old_mode = System.get_env("BOSS_CODEX_FIXTURE_MODE")
    old_data = Application.fetch_env!(:boss, :data_dir)
    bin = Path.join(ctx.root, "bin")
    source = Path.join(ctx.root, "repository")
    File.mkdir!(source)
    File.mkdir!(Path.join(source, "specs"))
    File.mkdir!(Path.join(ctx.root, "run-data"))
    {physical, 0} = System.cmd("/bin/pwd", ["-P"], cd: source)
    physical = String.trim(physical)

    ctx.project
    |> Ecto.Changeset.change(
      root_path: physical,
      git_common_dir: Path.join(physical, ".git"),
      specs_path: Path.join(physical, "specs")
    )
    |> Repo.update!()

    File.mkdir!(bin)
    File.cp!(Path.expand("../fixtures/codex_run.py", __DIR__), Path.join(bin, "codex"))
    File.chmod!(Path.join(bin, "codex"), 0o700)
    System.put_env("PATH", bin <> ":" <> old_path)
    System.put_env("BOSS_CODEX_FIXTURE_MODE", mode)
    Application.put_env(:boss, :data_dir, Path.join(ctx.root, "run-data"))

    on_exit(fn ->
      System.put_env("PATH", old_path)

      if old_mode,
        do: System.put_env("BOSS_CODEX_FIXTURE_MODE", old_mode),
        else: System.delete_env("BOSS_CODEX_FIXTURE_MODE")

      Application.put_env(:boss, :data_dir, old_data)
    end)

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

    File.write!(Path.join(source, "user.txt"), "local change")
  end

  defp wait_run(project, id, predicate, attempts \\ 300)

  defp wait_run(project, id, predicate, attempts) when attempts > 0 do
    run = Runs.get(project, id)

    cond do
      predicate.(run) ->
        run

      not Runs.active?(run) ->
        flunk("Unexpected run result #{inspect({run.status, run.reason})}")

      true ->
        Process.sleep(20)
        wait_run(project, id, predicate, attempts - 1)
    end
  end

  defp wait_run(_, _, _, 0), do: flunk("Run did not reach expected state")

  defp wait_file(path, attempts \\ 100)

  defp wait_file(path, attempts) when attempts > 0 do
    if File.exists?(path),
      do: :ok,
      else:
        (
          Process.sleep(20)
          wait_file(path, attempts - 1)
        )
  end

  defp wait_file(_, 0), do: flunk("Fixture did not write its readiness marker")

  defp start_manager(repo, worker) do
    start_supervised!(
      {Manager,
       [name: Boss.TestRunsManager, registry: Boss.TestRunsActive, repo: repo, worker: worker]}
    )
  end
end
