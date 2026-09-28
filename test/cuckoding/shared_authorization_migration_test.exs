defmodule Cuckoding.SharedAuthorizationMigrationTest do
  use ExUnit.Case, async: false

  defmodule MigrationRepo do
    use Ecto.Repo, otp_app: :cuckoding, adapter: Ecto.Adapters.SQLite3
  end

  test "upgrades copied schemas without changing existing account or project controls" do
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

    assert Ecto.Migrator.run(MigrationRepo, migrations, :up, to: 20_260_922_120_000, log: false) ==
             [
               20_260_920_170_000,
               20_260_922_120_000
             ]

    [after_row] = Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT * FROM provider_accounts").rows
    assert Enum.drop(after_row, -1) == hd(before)
    assert List.last(after_row) == nil
    assert Ecto.Adapters.SQL.query!(MigrationRepo, "PRAGMA foreign_key_check").rows == []

    assert Ecto.Adapters.SQL.query!(MigrationRepo, "PRAGMA table_info(project_autopilots)").rows !=
             []

    assert {:error, _} =
             Ecto.Adapters.SQL.query(
               MigrationRepo,
               "UPDATE provider_accounts SET authorization_account_id = 'missing' WHERE id = 'prior-agent'"
             )

    assert Ecto.Adapters.SQL.query!(MigrationRepo, "PRAGMA integrity_check").rows == [["ok"]]
    assert_completion_upgrade(migrations, root)
  end

  defp assert_completion_upgrade(migrations, root) do
    Ecto.Adapters.SQL.query!(MigrationRepo, """
    INSERT INTO projects (id, name, repo_path, default_branch, workspace_root, port_range_start, port_range_end, inserted_at, updated_at)
    VALUES ('prior-project', 'Preserved', '/repo', 'main', '/workspaces', 42000, 42010, '2026-09-22 00:00:00', '2026-09-22 00:00:00')
    """)

    Ecto.Adapters.SQL.query!(MigrationRepo, """
    INSERT INTO project_autopilots (project_id, state, max_active_runs, critical_blocker_limit, last_issue, inserted_at, updated_at)
    VALUES ('prior-project', 'attention', 3, 2, 'critical_blockers', '2026-09-22 00:00:00', '2026-09-22 00:00:00')
    """)

    before = Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT * FROM project_autopilots").rows
    copy = Path.join(root, "completion-copy.db")
    Ecto.Adapters.SQL.query!(MigrationRepo, "VACUUM INTO ?", [copy])
    stop_supervised!(MigrationRepo)
    start_supervised!({MigrationRepo, database: copy, pool_size: 1})

    assert Ecto.Migrator.run(MigrationRepo, migrations, :up, to: 20_260_924_120_000, log: false) ==
             [
               20_260_924_120_000
             ]

    [after_row] = Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT * FROM project_autopilots").rows
    assert Enum.drop(after_row, -1) == hd(before)
    assert List.last(after_row) == "manual"

    assert {:error, _} =
             Ecto.Adapters.SQL.query(
               MigrationRepo,
               "UPDATE project_autopilots SET completion_mode = 'release'"
             )

    assert Ecto.Adapters.SQL.query!(MigrationRepo, "PRAGMA foreign_key_check").rows == []
    assert Ecto.Adapters.SQL.query!(MigrationRepo, "PRAGMA integrity_check").rows == [["ok"]]
    assert_board_upgrade(migrations, root)
  end

  defp assert_board_upgrade(migrations, root) do
    now = "2026-09-25 00:00:00"

    for sql <- [
          "INSERT INTO project_config_versions (id, project_id, revision, source_hash, config_json, inserted_at) VALUES ('policy', 'prior-project', 1, 'hash', '{}', '#{now}')",
          "INSERT INTO workflow_versions (id, name, version, definition_json, published_at, inserted_at) VALUES ('flow', 'default', 1, '{}', '#{now}', '#{now}')",
          "INSERT INTO boards (id, project_id, workflow_version_id, name, inserted_at, updated_at) VALUES ('board', 'prior-project', 'flow', 'Preserved', '#{now}', '#{now}')",
          "INSERT INTO tasks (id, board_id, title, position, state, inserted_at, updated_at) VALUES ('task', 'board', 'Reviewed history', 0, 'done', '#{now}', '#{now}')",
          "INSERT INTO tasks (id, board_id, title, position, kind, inserted_at, updated_at) VALUES ('controller-two', 'board', 'Next controller', 1, 'board_intake', '#{now}', '#{now}')",
          "INSERT INTO runs (id, task_id, sequence, state, workflow_snapshot_json, policy_snapshot_id, branch, base_sha, inserted_at, updated_at) VALUES ('run', 'task', 1, 'done', '{}', 'policy', 'reviewed', 'base', '#{now}', '#{now}')"
        ],
        do: Ecto.Adapters.SQL.query!(MigrationRepo, sql)

    before = Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT * FROM runs").rows
    tasks = Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT * FROM tasks").rows
    copy = Path.join(root, "board-copy.db")
    Ecto.Adapters.SQL.query!(MigrationRepo, "VACUUM INTO ?", [copy])
    stop_supervised!(MigrationRepo)
    start_supervised!({MigrationRepo, database: copy, pool_size: 1})

    assert Ecto.Migrator.run(MigrationRepo, migrations, :up, to: 20_260_925_120_000, log: false) ==
             [
               20_260_925_120_000
             ]

    [after_row] = Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT * FROM runs").rows
    assert Enum.drop(after_row, -1) == hd(before)
    assert List.last(after_row) == nil
    assert Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT * FROM tasks").rows == tasks

    insert =
      "INSERT INTO board_executions (id, board_id, controller_task_id, base_sha, head_sha, snapshot_json, inserted_at, updated_at) VALUES (?, 'board', ?, 'base', 'base', '{}', '#{now}', '#{now}')"

    Ecto.Adapters.SQL.query!(MigrationRepo, insert, ["batch", "task"])

    assert {:error, _} =
             Ecto.Adapters.SQL.query(MigrationRepo, insert, ["duplicate", "controller-two"])

    Ecto.Adapters.SQL.query!(MigrationRepo, "UPDATE board_executions SET state = 'paused'")

    assert {:error, _} =
             Ecto.Adapters.SQL.query(MigrationRepo, insert, ["duplicate", "controller-two"])

    Ecto.Adapters.SQL.query!(MigrationRepo, "UPDATE board_executions SET state = 'stopped'")
    Ecto.Adapters.SQL.query!(MigrationRepo, insert, ["next-batch", "controller-two"])

    assert {:error, _} =
             Ecto.Adapters.SQL.query(
               MigrationRepo,
               "UPDATE runs SET board_execution_id = 'missing'"
             )

    assert Ecto.Adapters.SQL.query!(MigrationRepo, "PRAGMA foreign_key_check").rows == []
    assert Ecto.Adapters.SQL.query!(MigrationRepo, "PRAGMA integrity_check").rows == [["ok"]]
    assert_autonomy_upgrade(migrations, root)
  end

  defp assert_autonomy_upgrade(migrations, root) do
    before =
      Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT * FROM board_executions ORDER BY id").rows

    copy = Path.join(root, "autonomy-copy.db")
    Ecto.Adapters.SQL.query!(MigrationRepo, "VACUUM INTO ?", [copy])
    stop_supervised!(MigrationRepo)
    start_supervised!({MigrationRepo, database: copy, pool_size: 1})

    assert Ecto.Migrator.run(MigrationRepo, migrations, :up, all: true, log: false) == [
             20_260_928_120_000
           ]

    rows =
      Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT * FROM board_executions ORDER BY id").rows

    assert Enum.map(rows, &Enum.drop(&1, -2)) == before
    assert Enum.all?(rows, &(Enum.take(&1, -2) == ["fixed_batch", 0]))

    assert Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT * FROM board_plan_revisions").rows ==
             []

    assert Ecto.Adapters.SQL.query!(MigrationRepo, "PRAGMA foreign_key_check").rows == []
    assert Ecto.Adapters.SQL.query!(MigrationRepo, "PRAGMA integrity_check").rows == [["ok"]]
  end
end
