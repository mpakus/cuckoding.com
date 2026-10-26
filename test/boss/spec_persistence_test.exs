defmodule Boss.SpecPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Projects, Repo}

  @migrations [
    {20_261_025_180_000, Boss.Repo.Migrations.CreateProjects},
    {20_261_025_220_000, Boss.Repo.Migrations.CreateSpecRevisions},
    {20_261_025_230_000, Boss.Repo.Migrations.TrackMissingSpecs}
  ]

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "boss-spec-db-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(directory)
    on_exit(fn -> remove_scratch(directory, 20) end)
    {:ok, lock} = Boss.DataDirectory.acquire(directory)
    on_exit(fn -> Boss.DataDirectory.release(lock) end)

    opts = [
      name: nil,
      database: Path.join(directory, "boss.db"),
      pool: DBConnection.ConnectionPool,
      pool_size: 2
    ]

    repo = start_supervised!({Repo, opts})
    Repo.put_dynamic_repo(repo)
    Ecto.Migrator.run(Repo, @migrations, :up, to: 20_261_025_180_000, log: false)
    project_root = Path.join(directory, "repository")
    File.mkdir!(project_root)
    File.mkdir!(Path.join(project_root, "specs"))

    project =
      Repo.insert!(%Boss.Projects.Project{
        name: "Before migration",
        root_path: project_root,
        git_common_dir: Path.join(project_root, ".git"),
        specs_path: Path.join(project_root, "specs"),
        base_branch: "main"
      })

    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)
    %{repo: repo, opts: opts, project: project}
  end

  test "upgrade preserves projects and committed revisions survive a Repo restart", %{
    opts: opts,
    project: project
  } do
    {:ok, first} = Projects.record_spec(project.id, observation("A"))
    {:ok, second} = Projects.record_spec(project.id, observation("B"))
    assert :ok = stop_supervised(Repo)
    restarted = start_supervised!({Repo, opts})
    Repo.put_dynamic_repo(restarted)
    assert Projects.get_project!(project.id) == project
    assert Projects.list_spec_revisions(first.spec.id) == [first.revision, second.revision]
    assert Repo.get!(Boss.Tasks.Task, first.task.id) == first.task

    assert {:ok, %{change: :unchanged, task: task}} =
             Projects.record_spec(project.id, observation("B"))

    assert task.spec_revision_id == first.revision.id
  end

  test "concurrent observations produce one identity, one revision and one task", %{
    repo: repo,
    project: project
  } do
    results =
      1..8
      |> Task.async_stream(
        fn _ ->
          Repo.put_dynamic_repo(repo)
          Projects.record_spec(project.id, observation("same"))
        end,
        max_concurrency: 4,
        timeout: 10_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1))
    changes = Enum.map(results, fn {:ok, {:ok, result}} -> result.change end)
    assert Enum.count(changes, &(&1 == :created)) == 1
    assert Enum.count(changes, &(&1 == :unchanged)) == 7
    assert Repo.aggregate("specs", :count) == 1
    assert Repo.aggregate("spec_revisions", :count) == 1
    assert Repo.aggregate("tasks", :count) == 1
  end

  test "migration rollback and reapply preserve the pre-existing project", %{project: project} do
    {:ok, _} = Projects.record_spec(project.id, observation("A"))

    assert [20_261_025_230_000, 20_261_025_220_000] =
             Ecto.Migrator.run(Repo, @migrations, :down, step: 2, log: false)

    assert Projects.get_project!(project.id) == project

    assert [20_261_025_220_000, 20_261_025_230_000] =
             Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)

    assert {:ok, %{change: :created}} = Projects.record_spec(project.id, observation("A"))
  end

  test "rollback refuses to discard retained histories that share a reused path", %{
    project: project
  } do
    {:ok, first} = Projects.record_spec(project.id, observation("A"))
    first.spec |> Ecto.Changeset.change(missing: true) |> Repo.update!()

    {:ok, second} =
      Projects.record_spec(project.id, Map.put(observation("B"), :explicit_id, "replacement"))

    assert_raise Exqlite.Error, ~r/UNIQUE constraint failed/, fn ->
      Ecto.Migrator.run(Repo, @migrations, :down, step: 1, log: false)
    end

    assert [%{missing: true}, %{missing: false}] = Projects.list_spec_entries(project.id)
    assert Projects.list_spec_revisions(first.spec.id) == [first.revision]
    assert Projects.list_spec_revisions(second.spec.id) == [second.revision]
  end

  test "concurrent full syncs share one current snapshot and survive restart", %{
    repo: repo,
    opts: opts,
    project: project
  } do
    File.write!(Path.join(project.specs_path, "spec.md"), "# First")

    results =
      1..4
      |> Task.async_stream(
        fn _ ->
          Repo.put_dynamic_repo(repo)
          Boss.Projects.SpecImporter.sync(project.id)
        end,
        max_concurrency: 4,
        timeout: 15_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1))
    assert Repo.aggregate("spec_revisions", :count) == 1
    [entry] = Projects.list_spec_entries(project.id)
    :ok = stop_supervised(Repo)
    restarted = start_supervised!({Repo, opts})
    Repo.put_dynamic_repo(restarted)
    assert Projects.list_spec_entries(project.id) == [entry]
    File.rm!(Path.join(project.specs_path, "spec.md"))
    assert {:ok, %{missing: 1}} = Boss.Projects.SpecImporter.sync(project.id)
    assert Repo.aggregate("spec_revisions", :count) == 1
  end

  test "manual and automatic scans cannot overlap inside SQLite", %{repo: repo, project: project} do
    File.write!(Path.join(project.specs_path, "one.md"), "# Shared")
    observer = self()
    handler = make_ref()
    first = :atomics.new(1, [])

    :telemetry.attach(
      handler,
      [:boss, :repo, :query],
      fn _, _, metadata, _ ->
        if metadata.source == "projects" and String.starts_with?(metadata.query, "SELECT") do
          send(observer, {:scan_started, self()})

          if :atomics.compare_exchange(first, 1, 0, 1) == :ok do
            receive do
              :continue_scan -> :ok
            end
          end
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    automatic =
      Task.async(fn ->
        Repo.put_dynamic_repo(repo)
        Boss.Projects.SpecImporter.sync(project.id, settle_ms: 20)
      end)

    assert_receive {:scan_started, worker}, 1000

    manual =
      Task.async(fn ->
        Repo.put_dynamic_repo(repo)
        Boss.Projects.SpecImporter.sync(project.id)
      end)

    refute_receive {:scan_started, _}, 50
    send(worker, :continue_scan)
    assert {:ok, %{created: 1}} = Task.await(automatic)
    assert_receive {:scan_started, _}, 1000
    assert {:ok, %{unchanged: 1}} = Task.await(manual)
    assert Repo.aggregate("spec_revisions", :count) == 1
  end

  test "watcher startup after committed Repo restart rescans and retains inaccessible history", %{
    repo: repo,
    opts: opts,
    project: project
  } do
    path = Path.join(project.specs_path, "one.md")
    File.write!(path, "# Before restart")
    assert {:ok, _} = Boss.Projects.SpecImporter.sync(project.id)
    [first] = Projects.list_spec_entries(project.id)
    assert :ok = stop_supervised(Repo)
    restarted = start_supervised!({Repo, opts})
    assert restarted != repo
    Repo.put_dynamic_repo(restarted)
    File.write!(path, "# After restart")
    Boss.Projects.SpecWatcher.subscribe(project.id)

    start_supervised!(
      {Boss.Projects.SpecWatcher, repo: restarted, interval_ms: 10_000, settle_ms: 10}
    )

    assert_receive {:spec_sync, _, {:ok, %{revised: 1}}}, 2000

    assert [%{id: id, latest_revision: 2, task_revision: 1}] =
             Projects.list_spec_entries(project.id)

    assert id == first.id
    assert :ok = stop_supervised(Boss.Projects.SpecWatcher)
    File.rename!(project.specs_path, project.specs_path <> "-unavailable")

    start_supervised!(
      {Boss.Projects.SpecWatcher, repo: restarted, interval_ms: 10_000, settle_ms: 10}
    )

    assert_receive {:spec_sync, _, {:error, [_ | _]}}, 2000
    assert [%{missing: false, latest_revision: 2}] = Projects.list_spec_entries(project.id)
    assert Repo.aggregate("spec_revisions", :count) == 2
  end

  # Exqlite close_v2 defers statement finalization; WAL sidecars can outlive Repo briefly.
  # Retry only this test's exclusively created root, after supervised children stop.
  defp remove_scratch(directory, retries) do
    case File.rm_rf(directory) do
      {:ok, _} ->
        :ok

      {:error, reason, _} when reason in [:eexist, :enotempty] and retries > 0 ->
        Process.sleep(10)
        remove_scratch(directory, retries - 1)

      {:error, reason, file} ->
        raise File.Error, reason: reason, action: "remove scratch directory", path: file
    end
  end

  defp observation(text), do: %{relative_path: "spec.md", original_text: text, title: "Spec"}
end
