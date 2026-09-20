defmodule Cuckoding.SharedAuthorizationMigrationTest do
  use ExUnit.Case, async: false

  defmodule MigrationRepo do
    use Ecto.Repo, otp_app: :cuckoding, adapter: Ecto.Adapters.SQLite3
  end

  test "upgrades a copy of the prior schema without changing existing account data" do
    root =
      Path.join(
        System.tmp_dir!(),
        "authorization-migration-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    source = Path.join(root, "prior.db")
    copy = Path.join(root, "copy.db")
    start_supervised!({MigrationRepo, database: source, pool_size: 1})
    migrations = Application.app_dir(:cuckoding, "priv/repo/migrations")
    Ecto.Migrator.run(MigrationRepo, migrations, :up, to: 20_260_919_090_000, log: false)

    Ecto.Adapters.SQL.query!(MigrationRepo, """
    INSERT INTO provider_accounts (id, adapter_key, label, auth_mode, status, capabilities_json, inserted_at, updated_at)
    VALUES ('prior-agent', 'codex', 'Keep me', 'os_keyring', 'authenticated', '{}', '2026-09-20 00:00:00', '2026-09-20 00:00:00')
    """)

    before = Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT * FROM provider_accounts").rows
    Ecto.Adapters.SQL.query!(MigrationRepo, "VACUUM INTO ?", [copy])
    stop_supervised!(MigrationRepo)
    start_supervised!({MigrationRepo, database: copy, pool_size: 1})

    assert Ecto.Migrator.run(MigrationRepo, migrations, :up, all: true, log: false) == [
             20_260_920_170_000
           ]

    [after_row] = Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT * FROM provider_accounts").rows
    assert Enum.drop(after_row, -1) == hd(before)
    assert List.last(after_row) == nil
    assert Ecto.Adapters.SQL.query!(MigrationRepo, "PRAGMA foreign_key_check").rows == []

    assert {:error, _} =
             Ecto.Adapters.SQL.query(
               MigrationRepo,
               "UPDATE provider_accounts SET authorization_account_id = 'missing' WHERE id = 'prior-agent'"
             )

    assert Ecto.Adapters.SQL.query!(MigrationRepo, "PRAGMA integrity_check").rows == [["ok"]]
  end
end
