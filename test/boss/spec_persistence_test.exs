defmodule Boss.SpecPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Projects, Repo, Tasks}

  @migrations [
    {20_261_025_180_000, Boss.Repo.Migrations.CreateProjects},
    {20_261_025_220_000, Boss.Repo.Migrations.CreateSpecRevisions},
    {20_261_025_230_000, Boss.Repo.Migrations.TrackMissingSpecs},
    {20_261_026_010_000, Boss.Repo.Migrations.CreateTaskEvents}
  ]

  setup context do
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
      name: Map.get(context, :repo_name),
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

    Ecto.Migrator.run(Repo, @migrations, :up,
      to: Map.get(context, :migrate_to, 20_261_026_010_000),
      log: false
    )

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

    assert [20_261_026_010_000, 20_261_025_230_000, 20_261_025_220_000] =
             Ecto.Migrator.run(Repo, @migrations, :down,
               to_exclusive: 20_261_025_180_000,
               log: false
             )

    assert Projects.get_project!(project.id) == project

    assert [20_261_025_220_000, 20_261_025_230_000, 20_261_026_010_000] =
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

    assert [20_261_026_010_000] =
             Ecto.Migrator.run(Repo, @migrations, :down,
               to_exclusive: 20_261_025_230_000,
               log: false
             )

    assert_raise Exqlite.Error, ~r/UNIQUE constraint failed/, fn ->
      Ecto.Migrator.run(Repo, @migrations, :down, to: 20_261_025_230_000, log: false)
    end

    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)
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

  test "identical concurrent transition commands commit one receipt and one version", %{
    repo: repo,
    project: project
  } do
    {:ok, saved} = Projects.record_spec(project.id, observation("Pinned source"))
    command = transition_command("same-command", "block", 0, "Waiting for a decision")
    results = transition_concurrently(repo, saved.task.id, List.duplicate(command, 8))
    assert [{:ok, event}] = Enum.uniq(results)
    assert event.__struct__ == Boss.Tasks.Event
    assert event.version == 1
    assert event.from_state == "new"
    assert event.to_state == "blocked"
    assert event.spec_revision_id == saved.revision.id
    assert Tasks.list_events(saved.task.id) == [event]

    assert %{state: "blocked", state_version: 1, recovery_state: "new"} =
             Tasks.get_task!(saved.task.id)

    assert Tasks.get_task!(saved.task.id).attention_reason == command.reason
  end

  test "distinct commands competing for one version have exactly one winner", %{
    repo: repo,
    project: project
  } do
    {:ok, saved} = Projects.record_spec(project.id, observation("Pinned source"))

    results =
      transition_concurrently(repo, saved.task.id, [
        transition_command("block", "block", 0, "Waiting"),
        transition_command("question", "needs_input", 0, "Which option?")
      ])

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :stale_state})) == 1
    {:ok, event} = Enum.find(results, &match?({:ok, _}, &1))
    assert Tasks.list_events(saved.task.id) == [event]
    task = Tasks.get_task!(saved.task.id)
    assert task.state_version == 1
    assert task.state == event.to_state
    assert task.attention_reason == event.reason
  end

  test "committed task events survive restart and older commands replay their original receipt",
       %{
         repo: repo,
         opts: opts,
         project: project
       } do
    {:ok, saved} = Projects.record_spec(project.id, observation("Original source"))
    {:ok, _} = Projects.record_spec(project.id, observation("Changed source"))
    block = transition_command("first", "block", 0, "Waiting")
    assert {:ok, first} = Tasks.transition(saved.task.id, block)
    resume = transition_command("second", "resume", 1)
    assert {:ok, second} = Tasks.transition(saved.task.id, resume)
    task = Tasks.get_task!(saved.task.id)
    assert task.state == "new"
    assert task.state_version == 2
    assert task.attention_reason == nil
    assert task.recovery_state == nil
    assert first.spec_revision_id == saved.revision.id
    assert second.spec_revision_id == saved.revision.id
    assert :ok = stop_supervised(Repo)
    restarted = start_supervised!({Repo, opts})
    assert restarted != repo
    Repo.put_dynamic_repo(restarted)

    assert Tasks.get_task!(saved.task.id) == task
    assert Tasks.list_events(saved.task.id) == [first, second]
    assert {:ok, ^first} = Tasks.transition(saved.task.id, block)
    assert {:ok, ^second} = Tasks.transition(saved.task.id, Map.delete(resume, :reason))

    assert {:error, :idempotency_conflict} =
             Tasks.transition(saved.task.id, %{block | reason: "Different reason"})

    assert Tasks.get_task!(saved.task.id) == task
    assert Tasks.list_events(saved.task.id) == [first, second]
  end

  @tag repo_restart_regression: true, repo_name: Boss.TransitionPersistenceRepo
  test "a transition cannot move from a stopped named Repo into its replacement pool", %{
    repo: repo,
    opts: opts,
    project: project
  } do
    {:ok, saved} = Projects.record_spec(project.id, observation("Original source"))
    command = transition_command("during-restart", "block", 0, "Waiting")
    replacement = Keyword.put(opts, :database, opts[:database] <> ".replacement")
    # Isolate name reuse from the stopped connection's still-held SQLite write lock.
    Repo.query!("VACUUM INTO ?", [replacement[:database]])
    {:ok, database} = Exqlite.Sqlite3.open(replacement[:database])

    try do
      :ok = Exqlite.Sqlite3.execute(database, "PRAGMA journal_mode=WAL")
    after
      Exqlite.Sqlite3.close(database)
    end

    observer = self()
    cache = Ecto.Repo.Registry.lookup(repo).cache
    assert :ets.info(cache, :owner) == repo

    # Let the paused SELECT finish its cache bookkeeping after its Repo stops.
    :sys.replace_state(repo, fn state ->
      :ets.setopts(cache, {:heir, observer, :old_query_cache})
      state
    end)

    first = :atomics.new(1, [])
    handler = make_ref()

    :telemetry.attach(
      handler,
      [:boss, :repo, :query],
      fn _, _, metadata, _ ->
        if metadata.source == "tasks" and String.starts_with?(metadata.query, "SELECT") and
             :atomics.compare_exchange(first, 1, 0, 1) == :ok do
          send(observer, {:task_loaded, self()})

          receive do
            :continue_transition -> :ok
          end
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    selector = opts[:name]

    transition =
      Task.async(fn ->
        Repo.put_dynamic_repo(selector)
        result = Tasks.transition(saved.task.id, command)
        {result, Repo.get_dynamic_repo()}
      end)

    assert_receive {:task_loaded, worker}, 1_000
    assert :ok = stop_supervised(Repo)
    assert_receive {:"ETS-TRANSFER", ^cache, ^repo, :old_query_cache}
    restarted = start_supervised!({Repo, replacement})
    assert restarted != repo
    Repo.put_dynamic_repo(restarted)

    Repo.query!(
      "CREATE TRIGGER reject_restarted_event BEFORE INSERT ON task_events " <>
        "BEGIN SELECT RAISE(ABORT, 'test failure'); END"
    )

    send(worker, :continue_transition)
    assert {{:error, :storage_error}, ^selector} = Task.await(transition, 10_000)
    assert Tasks.list_events(saved.task.id) == []
    assert Tasks.get_task!(saved.task.id) == saved.task
    Repo.query!("DROP TRIGGER reject_restarted_event")
    assert {:ok, %{version: 1}} = Tasks.transition(saved.task.id, command)
    assert %{state: "blocked", state_version: 1} = Tasks.get_task!(saved.task.id)
  end

  @tag repo_restart_regression: true, repo_name: Boss.TransitionPersistenceRepo
  test "unavailable Repo names and dead PIDs return storage errors and retain the selector", %{
    repo: repo,
    opts: opts,
    project: project
  } do
    {:ok, saved} = Projects.record_spec(project.id, observation("Original source"))
    assert :ok = stop_supervised(Repo)

    for selector <- [opts[:name], repo] do
      Repo.put_dynamic_repo(selector)

      assert {:error, :storage_error} =
               Tasks.transition(
                 saved.task.id,
                 transition_command("dead-repo", "cancel", 0, "Stop")
               )

      assert Repo.get_dynamic_repo() == selector
    end
  end

  test "task event rollback refuses to discard retained history or recovery state", %{
    project: project
  } do
    {:ok, saved} = Projects.record_spec(project.id, observation("Original source"))

    assert {:ok, event} =
             Tasks.transition(saved.task.id, transition_command("block", "block", 0, "Waiting"))

    task = Tasks.get_task!(saved.task.id)

    assert_raise Ecto.MigrationError, "cannot discard retained task events", fn ->
      Ecto.Migrator.run(Repo, @migrations, :down,
        to_exclusive: 20_261_025_230_000,
        log: false
      )
    end

    assert Tasks.get_task!(saved.task.id) == task
    assert Tasks.list_events(saved.task.id) == [event]
    assert 20_261_026_010_000 in Ecto.Migrator.migrated_versions(Repo)

    assert {:error, _} =
             Repo.query("UPDATE task_events SET reason = 'changed' WHERE id = ?", [event.id])

    assert {:error, _} = Repo.query("DELETE FROM task_events WHERE id = ?", [event.id])
    assert Tasks.list_events(saved.task.id) == [event]
  end

  @tag migrate_to: 20_261_025_230_000
  test "task event migration upgrades existing tasks and reverses without deleting them", %{
    project: project
  } do
    spec =
      Repo.insert!(%Boss.Projects.Spec{
        project_id: project.id,
        relative_path: "legacy.md",
        identity_key: "path:legacy.md"
      })

    revision =
      Repo.insert!(%Boss.Projects.SpecRevision{
        spec_id: spec.id,
        number: 1,
        relative_path: "legacy.md",
        content_hash: Base.encode16(:crypto.hash(:sha256, "Legacy source"), case: :lower),
        original_text: "Legacy source"
      })

    # Insert old columns explicitly: the current task schema includes fields not yet migrated.
    timestamp = DateTime.to_iso8601(revision.inserted_at)

    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO tasks (spec_id, spec_revision_id, title, state, inserted_at, updated_at) " <>
          "VALUES (?, ?, 'Legacy task', 'new', ?, ?) RETURNING id",
        [spec.id, revision.id, timestamp, timestamp]
      )

    assert [20_261_026_010_000] =
             Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)

    task = Tasks.get_task!(id)
    assert task.title == "Legacy task"
    assert task.state == "new"
    assert task.state_version == 0
    assert task.attention_reason == nil
    assert task.recovery_state == nil
    assert task.spec_revision_id == revision.id
    assert Tasks.list_events(id) == []

    assert [20_261_026_010_000] =
             Ecto.Migrator.run(Repo, @migrations, :down,
               to_exclusive: 20_261_025_230_000,
               log: false
             )

    assert %{rows: [[^id, "Legacy task", "new", revision_id]]} =
             Repo.query!("SELECT id, title, state, spec_revision_id FROM tasks WHERE id = ?", [id])

    assert revision_id == revision.id

    assert [20_261_026_010_000] =
             Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)

    assert Tasks.get_task!(id) == task
    assert Tasks.list_events(id) == []

    assert {:ok, %{version: 1}} =
             Tasks.transition(id, transition_command("cancel", "cancel", 0, "Stop"))
  end

  defp transition_concurrently(repo, task_id, commands) do
    tasks =
      Enum.map(commands, fn command ->
        Task.async(fn ->
          Repo.put_dynamic_repo(repo)

          receive do
            :transition -> Tasks.transition(task_id, command)
          end
        end)
      end)

    Enum.each(tasks, &send(&1.pid, :transition))
    Enum.map(tasks, &Task.await(&1, 10_000))
  end

  defp transition_command(id, action, version, reason \\ nil),
    do: %{command_id: id, action: action, expected_version: version, reason: reason}

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
