defmodule Cuckoding.BattleCapacityMigrationTest do
  use ExUnit.Case, async: false

  defmodule MigrationRepo do
    use Ecto.Repo, otp_app: :cuckoding, adapter: Ecto.Adapters.SQLite3
  end

  test "prior schema upgrades without changing facts and its verified backup remains readable" do
    root = "/private/tmp/cuckoding-capacity-migration-#{Ecto.UUID.generate()}"
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    database = Path.join(root, "previous.sqlite3")
    backup = Path.join(root, "before-upgrade.sqlite3")

    start_supervised!(
      {MigrationRepo, database: database, pool: DBConnection.ConnectionPool, pool_size: 1}
    )

    path = Application.app_dir(:cuckoding, "priv/repo/migrations")
    previous = Ecto.Migrator.run(MigrationRepo, path, :up, to: 20_261_014_000_000, log: false)
    assert length(previous) == 11

    MigrationRepo.query!(
      "INSERT INTO events(kind, data, occurred_at) VALUES (?, ?, CURRENT_TIMESTAMP)",
      ["preserved", Jason.encode!(%{"sentinel" => "keep"})]
    )

    before = MigrationRepo.query!("SELECT * FROM events").rows
    MigrationRepo.query!("VACUUM INTO ?", [backup])
    File.chmod!(backup, 0o600)
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows

    migrated = Ecto.Migrator.run(MigrationRepo, path, :up, all: true, log: false)
    assert 20_261_021_000_000 in migrated
    assert 20_261_021_010_000 in migrated
    assert 20_261_021_020_000 in migrated
    assert 20_261_022_000_000 in migrated

    assert MigrationRepo.query!("SELECT * FROM events").rows == before
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows

    plan =
      MigrationRepo.query!(
        "EXPLAIN QUERY PLAN SELECT 1 FROM battle_attempts WHERE role IS NOT NULL AND json_extract(request, '$.role.agent_id') = 'codex' AND coalesce(json_extract(result, '$.cleanup_verified'), 0) != 1 LIMIT 1"
      ).rows

    assert inspect(plan) =~ "battle_attempts_uncertain_connection"

    event_plan =
      MigrationRepo.query!(
        "EXPLAIN QUERY PLAN SELECT id FROM events WHERE json_extract(data, '$.arena_id') = 'arena' AND id < 100 ORDER BY id DESC LIMIT 21"
      ).rows

    assert inspect(event_plan) =~ "events_arena_sequence"
    stop_supervised!(MigrationRepo)

    start_supervised!(
      {MigrationRepo, database: backup, pool: DBConnection.ConnectionPool, pool_size: 1}
    )

    assert MigrationRepo.query!("SELECT * FROM events").rows == before
    assert length(Ecto.Migrator.migrated_versions(MigrationRepo)) == 11
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows
  end

  test "fourteen-schema task claim indexes upgrade with existing claims and backup intact" do
    root = "/private/tmp/cuckoding-wave-migration-#{Ecto.UUID.generate()}"
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    database = Path.join(root, "prior.sqlite3")
    backup = Path.join(root, "before-upgrade.sqlite3")

    start_supervised!(
      {MigrationRepo, database: database, pool: DBConnection.ConnectionPool, pool_size: 1}
    )

    path = Application.app_dir(:cuckoding, "priv/repo/migrations")

    assert length(Ecto.Migrator.run(MigrationRepo, path, :up, to: 20_261_021_020_000, log: false)) ==
             14

    retained_tables = legacy_claim_rows()
    facts = Map.new(retained_tables, &{&1, MigrationRepo.query!("SELECT * FROM " <> &1).rows})

    MigrationRepo.query!(
      "INSERT INTO events(kind, data, occurred_at) VALUES ('wave-preserved', '{}', CURRENT_TIMESTAMP)"
    )

    before = MigrationRepo.query!("SELECT * FROM events").rows
    MigrationRepo.query!("VACUUM INTO ?", [backup])
    File.chmod!(backup, 0o600)

    assert Ecto.Migrator.run(MigrationRepo, path, :up, to: 20_261_022_000_000, log: false) == [
             20_261_022_000_000
           ]

    indexes =
      MigrationRepo.query!(
        "SELECT name, sql FROM sqlite_master WHERE type = 'index' AND tbl_name = 'battle_attempts'"
      ).rows

    assert Enum.any?(indexes, fn [name, sql] ->
             name == "battle_attempts_one_running_task" and sql =~ "task_id IS NOT NULL"
           end)

    assert Enum.any?(indexes, fn [name, sql] ->
             name == "battle_attempts_one_running_final" and sql =~ "task_id IS NULL"
           end)

    refute Enum.any?(indexes, fn [name, _] -> name == "battle_attempts_one_running" end)

    assert Map.new(retained_tables, &{&1, MigrationRepo.query!("SELECT * FROM " <> &1).rows}) ==
             facts

    assert MigrationRepo.query!("SELECT * FROM events").rows == before
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows
    stop_supervised!(MigrationRepo)

    start_supervised!(
      {MigrationRepo, database: backup, pool: DBConnection.ConnectionPool, pool_size: 1}
    )

    assert length(Ecto.Migrator.migrated_versions(MigrationRepo)) == 14

    assert Map.new(retained_tables, &{&1, MigrationRepo.query!("SELECT * FROM " <> &1).rows}) ==
             facts

    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows
    assert MigrationRepo.query!("SELECT * FROM events").rows == before
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
  end

  test "workflow ledger upgrades a backed-up fifteen-schema copy without rewriting facts" do
    root = "/private/tmp/cuckoding-workflow-migration-#{Ecto.UUID.generate()}"
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    database = Path.join(root, "prior.sqlite3")
    backup = Path.join(root, "before-upgrade.sqlite3")

    start_supervised!(
      {MigrationRepo, database: database, pool: DBConnection.ConnectionPool, pool_size: 1}
    )

    path = Application.app_dir(:cuckoding, "priv/repo/migrations")

    assert length(Ecto.Migrator.run(MigrationRepo, path, :up, to: 20_261_022_000_000, log: false)) ==
             15

    tables = legacy_claim_rows()
    facts = Map.new(tables, &{&1, MigrationRepo.query!("SELECT * FROM " <> &1).rows})
    MigrationRepo.query!("VACUUM INTO ?", [backup])
    File.chmod!(backup, 0o600)

    assert Ecto.Migrator.run(MigrationRepo, path, :up, to: 20_261_022_010_000, log: false) == [
             20_261_022_010_000
           ]

    assert Map.new(tables, &{&1, MigrationRepo.query!("SELECT * FROM " <> &1).rows}) == facts
    assert MigrationRepo.query!("SELECT * FROM workflow_revisions").rows == []
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows
    stop_supervised!(MigrationRepo)

    start_supervised!(
      {MigrationRepo, database: backup, pool: DBConnection.ConnectionPool, pool_size: 1}
    )

    assert length(Ecto.Migrator.migrated_versions(MigrationRepo)) == 15
    assert Map.new(tables, &{&1, MigrationRepo.query!("SELECT * FROM " <> &1).rows}) == facts
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows
  end

  test "writer checkpoint migration preserves schema sixteen and its readable backup" do
    root = "/private/tmp/cuckoding-writer-migration-#{Ecto.UUID.generate()}"
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    database = Path.join(root, "prior.sqlite3")
    backup = Path.join(root, "before-upgrade.sqlite3")

    start_supervised!(
      {MigrationRepo, database: database, pool: DBConnection.ConnectionPool, pool_size: 1}
    )

    path = Application.app_dir(:cuckoding, "priv/repo/migrations")

    assert length(Ecto.Migrator.run(MigrationRepo, path, :up, to: 20_261_022_010_000, log: false)) ==
             16

    tables = legacy_claim_rows() ++ ["workflow_revisions"]
    facts = Map.new(tables, &{&1, MigrationRepo.query!("SELECT * FROM " <> &1).rows})
    MigrationRepo.query!("VACUUM INTO ?", [backup])
    File.chmod!(backup, 0o600)

    assert Ecto.Migrator.run(MigrationRepo, path, :up, to: 20_261_023_000_000, log: false) == [
             20_261_023_000_000
           ]

    assert Map.new(tables, &{&1, MigrationRepo.query!("SELECT * FROM " <> &1).rows}) == facts
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows

    plan =
      MigrationRepo.query!(
        "EXPLAIN QUERY PLAN SELECT * FROM battle_attempts WHERE battle_id = 'battle' AND task_id = 'task' AND state = 'completed' AND stage = 'implementor' AND json_extract(request, '$.task_context.preparation.key') = 'preparation' LIMIT 6"
      ).rows

    assert inspect(plan) =~ "battle_attempts_writer_checkpoint"
    stop_supervised!(MigrationRepo)

    start_supervised!(
      {MigrationRepo, database: backup, pool: DBConnection.ConnectionPool, pool_size: 1}
    )

    assert length(Ecto.Migrator.migrated_versions(MigrationRepo)) == 16
    assert Map.new(tables, &{&1, MigrationRepo.query!("SELECT * FROM " <> &1).rows}) == facts
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows
  end

  test "task-block admission upgrades a backed-up seventeen-schema copy without changing facts" do
    root = "/private/tmp/cuckoding-task-block-migration-#{Ecto.UUID.generate()}"
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    database = Path.join(root, "prior.sqlite3")
    backup = Path.join(root, "before-upgrade.sqlite3")

    start_supervised!(
      {MigrationRepo, database: database, pool: DBConnection.ConnectionPool, pool_size: 1}
    )

    path = Application.app_dir(:cuckoding, "priv/repo/migrations")

    assert length(Ecto.Migrator.run(MigrationRepo, path, :up, to: 20_261_023_000_000, log: false)) ==
             17

    tables = legacy_claim_rows()
    facts = Map.new(tables, &{&1, MigrationRepo.query!("SELECT * FROM " <> &1).rows})
    MigrationRepo.query!("VACUUM INTO ?", [backup])
    File.chmod!(backup, 0o600)

    assert Ecto.Migrator.run(MigrationRepo, path, :up, all: true, log: false) == [
             20_261_023_010_000,
             20_261_024_000_000,
             20_261_024_010_000,
             20_261_024_020_000
           ]

    assert Map.new(tables, &{&1, MigrationRepo.query!("SELECT * FROM " <> &1).rows}) == facts
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows

    assert [[sql]] =
             MigrationRepo.query!(
               "SELECT sql FROM sqlite_master WHERE type='trigger' AND name='battle_attempts_blocked_task'"
             ).rows

    assert sql =~ "task-local-continuation-v1" and sql =~ "needs_attention"
    stop_supervised!(MigrationRepo)

    start_supervised!(
      {MigrationRepo, database: backup, pool: DBConnection.ConnectionPool, pool_size: 1}
    )

    assert length(Ecto.Migrator.migrated_versions(MigrationRepo)) == 17
    assert Map.new(tables, &{&1, MigrationRepo.query!("SELECT * FROM " <> &1).rows}) == facts
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows
  end

  defp legacy_claim_rows do
    command = Ecto.UUID.generate()
    arena = Ecto.UUID.generate()
    board = Ecto.UUID.generate()
    task = Ecto.UUID.generate()
    battle = Ecto.UUID.generate()
    now = "2026-10-21 00:00:00.000000"

    rows = [
      {"commands", ~w(id kind expected_revision inserted_at updated_at),
       [command, "fixture", 0, now, now]},
      {"arenas",
       ~w(id command_id selection_id team_revision_id name path device inode git_entry inserted_at),
       [
         arena,
         command,
         command,
         1,
         "Retained",
         "/private/tmp/synthetic-migration-only",
         1,
         2,
         "directory",
         now
       ]},
      {"tabulae", ~w(id arena_id team_revision_id command_id name definition inserted_at),
       [board, arena, 1, command, "Retained", "{}", now]},
      {"draft_tasks",
       ~w(id tabula_id revision title description criteria column inserted_at updated_at),
       [task, board, 1, "Retained", "Keep", "Inspect", "specs", now, now]},
      {"battles",
       ~w(id arena_id tabula_id fingerprint snapshot state stage current_task_id deadline_at inserted_at updated_at),
       [
         battle,
         arena,
         board,
         String.duplicate("a", 64),
         ~s({"version":"arena-loop-v2","scheduler":"isolated-arenas-v1"}),
         "running",
         "implementor",
         task,
         now,
         now,
         now
       ]},
      {"battle_tasks", ~w(id battle_id task_id position snapshot inserted_at updated_at),
       [Ecto.UUID.generate(), battle, task, 0, "{}", now, now]},
      {"battle_attempts",
       ~w(id battle_id task_id stage role state claim_token request deadline_at inserted_at updated_at),
       [
         Ecto.UUID.generate(),
         battle,
         task,
         "implementor",
         "implementor",
         "running",
         Ecto.UUID.generate(),
         ~s({"retained":"claim"}),
         now,
         now,
         now
       ]}
    ]

    for {table, columns, values} <- rows do
      names = Enum.map_join(columns, ",", &("\"" <> &1 <> "\""))
      placeholders = Enum.map_join(values, ",", fn _ -> "?" end)

      MigrationRepo.query!(
        "INSERT INTO " <> table <> " (" <> names <> ") VALUES (" <> placeholders <> ")",
        values
      )
    end

    Enum.map(rows, &elem(&1, 0))
  end
end
