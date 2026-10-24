defmodule Cuckoding.UpgradeBackupTest do
  use ExUnit.Case, async: false
  alias Cuckoding.{Database, Storage, UpgradeBackup}

  defmodule BackupRepo do
    use Ecto.Repo, otp_app: :cuckoding, adapter: Ecto.Adapters.SQLite3
  end

  setup do
    root = "/private/tmp/cuckoding-upgrade-backup-#{Ecto.UUID.generate()}"
    Storage.prepare!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Application.put_env(:cuckoding, BackupRepo, database: Path.join(root, "foundation.db"))
    on_exit(fn -> Application.delete_env(:cuckoding, BackupRepo) end)

    start_supervised!(
      {BackupRepo,
       database: Path.join(root, "foundation.db"),
       pool: DBConnection.ConnectionPool,
       pool_size: 1,
       journal_mode: :wal}
    )

    path = Application.app_dir(:cuckoding, "priv/repo/migrations")
    %{root: root, path: path}
  end

  defp prior(path) do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert length(Ecto.Migrator.run(BackupRepo, path, :up, to: 20_261_023_000_000, log: false)) ==
               17
    end)

    BackupRepo.query!(
      ~s|INSERT INTO events(kind, data, occurred_at) VALUES ('backup-sentinel', '{"scope":"private fixture"}', CURRENT_TIMESTAMP)|
    )

    BackupRepo.query!("PRAGMA wal_checkpoint(PASSIVE)")

    BackupRepo.query!(
      "INSERT INTO events(kind, data, occurred_at) VALUES ('wal-sentinel', '{}', CURRENT_TIMESTAMP)"
    )

    BackupRepo.query!("SELECT * FROM events ORDER BY id").rows
  end

  test "a WAL-consistent verified private copy precedes migration and remains readable", %{
    root: root,
    path: path
  } do
    before = prior(path)
    :ok = Database.migrate!(BackupRepo, path)
    assert length(Ecto.Migrator.migrated_versions(BackupRepo)) == 21
    assert BackupRepo.query!("SELECT * FROM events ORDER BY id").rows == before
    observation = UpgradeBackup.observation(root)
    assert observation["status"] == "recorded"
    assert length(observation["from_versions"]) == 17
    assert length(observation["target_versions"]) == 21
    copy = Path.join(root, observation["relative_path"])
    assert Bitwise.band(File.stat!(copy).mode, 0o777) == 0o600

    assert :crypto.hash(:sha256, File.read!(copy)) |> Base.encode16(case: :lower) ==
             observation["sha256"]

    {:ok, reader} = Exqlite.start_link(database: copy, mode: :readonly)

    try do
      assert Exqlite.query!(reader, "SELECT count(*) FROM schema_migrations").rows == [[17]]
      assert Exqlite.query!(reader, "SELECT * FROM events ORDER BY id").rows == before
      assert Exqlite.query!(reader, "PRAGMA integrity_check").rows == [["ok"]]
      assert Exqlite.query!(reader, "PRAGMA foreign_key_check").rows == []
    after
      GenServer.stop(reader)
    end

    assert :crypto.hash(:sha256, File.read!(copy)) |> Base.encode16(case: :lower) ==
             observation["sha256"]
  end

  test "a linked backup destination refuses migration and preserves the source", %{
    root: root,
    path: path
  } do
    before = prior(path)
    outside = Path.join(root, "outside")
    File.mkdir!(outside)
    File.ln_s!(outside, Path.join(root, "backups"))

    assert_raise RuntimeError, ~r/pre-migration backup/, fn ->
      Database.migrate!(BackupRepo, path)
    end

    assert length(Ecto.Migrator.migrated_versions(BackupRepo)) == 17
    assert BackupRepo.query!("SELECT * FROM events ORDER BY id").rows == before
    assert File.ls!(outside) == []
  end

  test "fresh and current schemas do not create repeated backup work", %{root: root, path: path} do
    :ok = Database.migrate!(BackupRepo, path)
    assert UpgradeBackup.observation(root)["status"] == "none"
    refute File.exists?(Path.join(root, "backups"))
    :ok = Database.migrate!(BackupRepo, path)
    refute File.exists?(Path.join(root, "backups"))
  end

  test "an unknown nonempty database without migration history is not a fresh install", %{
    root: root,
    path: path
  } do
    BackupRepo.query!("CREATE TABLE retained_fixture(value TEXT)")
    BackupRepo.query!("INSERT INTO retained_fixture VALUES ('keep')")

    assert_raise RuntimeError, ~r/schema is unrecognized/, fn ->
      Database.migrate!(BackupRepo, path)
    end

    assert BackupRepo.query!("SELECT * FROM retained_fixture").rows == [["keep"]]
    assert Ecto.Migrator.migrated_versions(BackupRepo) == []
    refute File.exists?(Path.join(root, "backups"))
  end

  test "a current restart retains the exact immutable copy and receipt", %{root: root, path: path} do
    prior(path)
    :ok = Database.migrate!(BackupRepo, path)
    observation = UpgradeBackup.observation(root)
    files = File.ls!(Path.join(root, "backups")) |> Enum.sort()
    :ok = Database.migrate!(BackupRepo, path)
    assert UpgradeBackup.observation(root) == observation
    assert Enum.sort(File.ls!(Path.join(root, "backups"))) == files
  end

  test "malformed or linked metadata cannot be replaced by a new migration", %{
    root: root,
    path: path
  } do
    before = prior(path)
    backups = Path.join(root, "backups")
    File.mkdir!(backups)
    File.chmod!(backups, 0o700)
    pointer = Path.join(backups, "latest.json")
    File.write!(pointer, "{}")
    File.chmod!(pointer, 0o600)
    assert UpgradeBackup.observation(root)["status"] == "unavailable"

    assert_raise RuntimeError, ~r/pre-migration backup/, fn ->
      Database.migrate!(BackupRepo, path)
    end

    assert File.read!(pointer) == "{}"
    assert File.ls!(backups) == ["latest.json"]
    File.rm!(pointer)
    File.ln_s!(Path.join(root, ".ccoding-rebuild-v1"), pointer)

    assert_raise RuntimeError, ~r/pre-migration backup/, fn ->
      Database.migrate!(BackupRepo, path)
    end

    assert BackupRepo.query!("SELECT * FROM events ORDER BY id").rows == before
    assert length(Ecto.Migrator.migrated_versions(BackupRepo)) == 17
  end

  test "foreign key failures retain the partial attempt without migration or a receipt", %{
    root: root,
    path: path
  } do
    prior(path)
    BackupRepo.query!("CREATE TABLE invalid_fixture(agent_id TEXT REFERENCES agents(id))")
    BackupRepo.query!("PRAGMA foreign_keys=OFF")
    BackupRepo.query!("INSERT INTO invalid_fixture VALUES ('missing')")
    BackupRepo.query!("PRAGMA foreign_keys=ON")

    assert_raise RuntimeError, ~r/pre-migration backup/, fn ->
      Database.migrate!(BackupRepo, path)
    end

    assert length(Ecto.Migrator.migrated_versions(BackupRepo)) == 17
    [id] = File.ls!(Path.join(root, "backups"))
    assert {:ok, ^id} = Ecto.UUID.cast(id)
    assert File.stat!(Path.join([root, "backups", id, "foundation.db"])).size == 0
    refute File.exists?(Path.join([root, "backups", id, "receipt.json"]))
    assert UpgradeBackup.observation(root)["status"] == "none"
  end

  test "a hardlinked source refuses before changing its mode", %{root: root, path: path} do
    prior(path)
    source = Path.join(root, "foundation.db")
    File.chmod!(source, 0o640)
    File.ln!(source, Path.join(root, "source-link"))

    assert_raise RuntimeError, ~r/pre-migration backup/, fn ->
      Database.migrate!(BackupRepo, path)
    end

    assert Bitwise.band(File.stat!(source).mode, 0o777) == 0o640
    assert_raise RuntimeError, "unsafe private storage file", fn -> Storage.prepare!(root) end
    assert Bitwise.band(File.stat!(source).mode, 0o777) == 0o640
    assert length(Ecto.Migrator.migrated_versions(BackupRepo)) == 17
  end

  test "unsafe durability and future schemas refuse migration", %{root: root, path: path} do
    prior(path)
    BackupRepo.query!("PRAGMA synchronous=OFF")

    assert_raise RuntimeError, ~r/pre-migration backup/, fn ->
      Database.migrate!(BackupRepo, path)
    end

    assert length(Ecto.Migrator.migrated_versions(BackupRepo)) == 17
    before = File.ls!(Path.join(root, "backups"))
    BackupRepo.query!("PRAGMA synchronous=NORMAL")

    BackupRepo.query!(
      "INSERT INTO schema_migrations(version, inserted_at) VALUES (99999999999999, CURRENT_TIMESTAMP)"
    )

    assert_raise RuntimeError, ~r/schema is newer/, fn -> Database.migrate!(BackupRepo, path) end
    assert File.ls!(Path.join(root, "backups")) == before
    refute File.exists?(Path.join(root, "backups/latest.json"))
  end

  test "linked or oversized workspace markers refuse before reading or chmod", %{root: root} do
    marker = Path.join(root, ".ccoding-rebuild-v1")
    link = Path.join(root, "marker-link")
    File.chmod!(marker, 0o640)
    File.ln!(marker, link)
    assert_raise RuntimeError, "invalid rebuild data marker", fn -> Storage.prepare!(root) end
    assert Bitwise.band(File.stat!(marker).mode, 0o777) == 0o640
    assert UpgradeBackup.observation(root)["status"] == "unavailable"
    File.rm!(link)
    File.write!(marker, String.duplicate("x", 8192))
    assert_raise RuntimeError, "invalid rebuild data marker", fn -> Storage.prepare!(root) end
  end

  test "schema eighteen backs up before the new guest admission indexes", %{
    root: root,
    path: path
  } do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert length(Ecto.Migrator.run(BackupRepo, path, :up, to: 20_261_023_010_000, log: false)) ==
               18
    end)

    BackupRepo.query!(
      "INSERT INTO events(kind,data,occurred_at) VALUES ('eighteen-sentinel','{}',CURRENT_TIMESTAMP)"
    )

    before = BackupRepo.query!("SELECT * FROM events ORDER BY id").rows
    :ok = Database.migrate!(BackupRepo, path)
    assert BackupRepo.query!("SELECT * FROM events ORDER BY id").rows == before
    receipt = UpgradeBackup.observation(root)
    assert length(receipt["from_versions"]) == 18
    assert length(receipt["target_versions"]) == 21

    assert BackupRepo.query!(
             "SELECT name FROM sqlite_schema WHERE name IN ('battle_attempts_check_images','battle_attempts_guest_reservations') ORDER BY name"
           ).rows == [["battle_attempts_check_images"], ["battle_attempts_guest_reservations"]]
  end

  test "schema nineteen backs up before the task check compatibility fence", %{
    root: root,
    path: path
  } do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert length(Ecto.Migrator.run(BackupRepo, path, :up, to: 20_261_024_000_000, log: false)) ==
               19
    end)

    BackupRepo.query!(
      "INSERT INTO events(kind,data,occurred_at) VALUES ('nineteen-sentinel','{}',CURRENT_TIMESTAMP)"
    )

    before = BackupRepo.query!("SELECT * FROM events ORDER BY id").rows
    :ok = Database.migrate!(BackupRepo, path)
    assert BackupRepo.query!("SELECT * FROM events ORDER BY id").rows == before
    receipt = UpgradeBackup.observation(root)
    assert length(receipt["from_versions"]) == 19
    assert length(receipt["target_versions"]) == 21

    assert BackupRepo.query!(
             "SELECT name FROM sqlite_schema WHERE name='draft_task_verification_shape'"
           ).rows == [["draft_task_verification_shape"]]

    assert_raise Exqlite.Error, ~r/invalid task verification shape/, fn ->
      BackupRepo.query!(
        "INSERT INTO draft_task_revisions(task_id,command_id,revision,content,inserted_at) VALUES (?,?,1,?,CURRENT_TIMESTAMP)",
        [Ecto.UUID.generate(), Ecto.UUID.generate(), ~s({"verification":"not-an-array"})]
      )
    end
  end

  test "schema twenty is backed up before enabling check feedback", %{root: root, path: path} do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert length(Ecto.Migrator.run(BackupRepo, path, :up, to: 20_261_024_010_000, log: false)) ==
               20
    end)

    before = BackupRepo.query!("SELECT * FROM events ORDER BY id").rows
    :ok = Database.migrate!(BackupRepo, path)
    assert BackupRepo.query!("SELECT * FROM events ORDER BY id").rows == before
    receipt = UpgradeBackup.observation(root)
    assert length(receipt["from_versions"]) == 20
    assert length(receipt["target_versions"]) == 21

    assert BackupRepo.query!(
             "SELECT name FROM sqlite_schema WHERE name='battle_attempt_feedback_shape'"
           ).rows == [["battle_attempt_feedback_shape"]]
  end

  test "a later migration failure preserves the verified earlier database", %{
    root: root,
    path: path
  } do
    before = prior(path)
    migrations = Path.join(root, "migration-fixture")
    File.mkdir!(migrations)

    for file <- Path.wildcard(Path.join(path, "*.exs")) do
      File.cp!(file, Path.join(migrations, Path.basename(file)))
    end

    File.write!(Path.join(migrations, "20261025000000_fail_fixture.exs"), """
    defmodule Cuckoding.UpgradeBackupTest.FailFixture do
      use Ecto.Migration
      def up, do: raise("synthetic migration failure")
    end
    """)

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert_raise RuntimeError, "synthetic migration failure", fn ->
        Database.migrate!(BackupRepo, migrations)
      end
    end)

    assert BackupRepo.query!("SELECT * FROM events ORDER BY id").rows == before
    observation = UpgradeBackup.observation(root)
    assert observation["status"] == "recorded"
    assert length(observation["target_versions"]) == 22
    copy = Path.join(root, observation["relative_path"])
    {:ok, reader} = Exqlite.start_link(database: copy, mode: :readonly)

    try do
      assert Exqlite.query!(reader, "SELECT * FROM events ORDER BY id").rows == before
      assert Exqlite.query!(reader, "SELECT count(*) FROM schema_migrations").rows == [[17]]
    after
      GenServer.stop(reader)
    end
  end
end
