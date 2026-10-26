defmodule Boss.RunPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Repo, Projects, Runs}
  alias Boss.Runs.Manager

  @migrations [
    {20_261_025_180_000, Boss.Repo.Migrations.CreateProjects},
    {20_261_025_220_000, Boss.Repo.Migrations.CreateSpecRevisions},
    {20_261_025_230_000, Boss.Repo.Migrations.TrackMissingSpecs},
    {20_261_026_010_000, Boss.Repo.Migrations.CreateTaskEvents},
    {20_261_026_040_000, Boss.Repo.Migrations.CreateAgentRuns}
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

  defp start_manager(repo, worker) do
    start_supervised!(
      {Manager,
       [name: Boss.TestRunsManager, registry: Boss.TestRunsActive, repo: repo, worker: worker]}
    )
  end
end
