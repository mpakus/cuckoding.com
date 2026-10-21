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

    assert [20_261_021_000_000] ==
             Ecto.Migrator.run(MigrationRepo, path, :up, all: true, log: false)

    assert MigrationRepo.query!("SELECT * FROM events").rows == before
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows

    plan =
      MigrationRepo.query!(
        "EXPLAIN QUERY PLAN SELECT 1 FROM battle_attempts WHERE role IS NOT NULL AND json_extract(request, '$.role.agent_id') = 'codex' AND coalesce(json_extract(result, '$.cleanup_verified'), 0) != 1 LIMIT 1"
      ).rows

    assert inspect(plan) =~ "battle_attempts_uncertain_connection"
    stop_supervised!(MigrationRepo)

    start_supervised!(
      {MigrationRepo, database: backup, pool: DBConnection.ConnectionPool, pool_size: 1}
    )

    assert MigrationRepo.query!("SELECT * FROM events").rows == before
    assert length(Ecto.Migrator.migrated_versions(MigrationRepo)) == 11
    assert [["ok"]] = MigrationRepo.query!("PRAGMA integrity_check").rows
    assert [] == MigrationRepo.query!("PRAGMA foreign_key_check").rows
  end
end
