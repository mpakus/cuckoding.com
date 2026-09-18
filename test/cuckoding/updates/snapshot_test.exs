defmodule Cuckoding.Updates.SnapshotTest do
  use ExUnit.Case, async: true

  alias Cuckoding.Updates.Snapshot

  test "snapshot restores verified database, knowledge, and configuration without deleting extras" do
    root = temporary_directory()
    database = Path.join(root, "data/cuckoding.sqlite3")
    knowledge = Path.join(root, "project/.cuckoding/knowledge")
    configuration = Path.join(root, "project/.cuckoding/project.yml")
    backup_root = Path.join(root, "backups")

    File.mkdir_p!(Path.dirname(database))
    File.mkdir_p!(Path.join(knowledge, "facts"))
    File.write!(database, "database-before")
    File.write!(Path.join(knowledge, "facts/example.md"), "knowledge-before")
    File.write!(configuration, "version: 2")

    options = [
      database: database,
      backup_root: backup_root,
      database_backup: &File.cp/2,
      sources: [
        {"knowledge", "project", knowledge},
        {"configuration", "project", configuration}
      ]
    ]

    assert {:ok, snapshot} =
             Snapshot.create("attempt", %{"to_version" => "0.2.0"}, options)

    File.write!(database, "database-after")
    File.write!(Path.join(knowledge, "facts/example.md"), "knowledge-after")
    File.write!(configuration, "version: 3")
    File.write!(Path.join(knowledge, "facts/new.md"), "preserve-me")

    assert :ok = Snapshot.restore(snapshot.path, snapshot.manifest_hash, options)
    assert File.read!(database) == "database-before"
    assert File.read!(Path.join(knowledge, "facts/example.md")) == "knowledge-before"
    assert File.read!(configuration) == "version: 2"
    assert File.read!(Path.join(knowledge, "facts/new.md")) == "preserve-me"
    assert File.read!(Path.join(snapshot.path, "failed-current.sqlite3")) == "database-after"
  end

  test "snapshot rejects symlinked source entries and a changed manifest" do
    root = temporary_directory()
    database = Path.join(root, "cuckoding.sqlite3")
    knowledge = Path.join(root, "knowledge")
    File.write!(database, "database")
    File.mkdir_p!(knowledge)
    File.write!(Path.join(root, "outside.md"), "outside")
    File.ln_s!(Path.join(root, "outside.md"), Path.join(knowledge, "linked.md"))

    options = [
      database: database,
      backup_root: Path.join(root, "backups"),
      database_backup: &File.cp/2,
      sources: [{"knowledge", "project", knowledge}]
    ]

    assert {:error, {:snapshot_failed, {:unsafe_snapshot_source, _path}}} =
             Snapshot.create("unsafe", %{}, options)

    File.rm!(Path.join(knowledge, "linked.md"))
    assert {:ok, snapshot} = Snapshot.create("safe", %{}, options)

    assert {:error, :snapshot_manifest_mismatch} =
             Snapshot.restore(snapshot.path, String.duplicate("0", 64), options)
  end

  defp temporary_directory do
    directory =
      System.tmp_dir!()
      |> String.replace_prefix("/var/", "/private/var/")
      |> Path.join("cuckoding-update-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    directory
  end
end
