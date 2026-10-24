defmodule CuckodingWeb.UpgradeBackupLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest

  test "Settings exposes dated metadata, never database contents or a restore control", %{
    conn: conn
  } do
    root = "/private/tmp/cuckoding-backup-ui-#{Ecto.UUID.generate()}"
    Cuckoding.Storage.prepare!(root)
    original = Application.fetch_env!(:cuckoding, :data_dir)
    Application.put_env(:cuckoding, :data_dir, root)

    on_exit(fn ->
      Application.put_env(:cuckoding, :data_dir, original)
      File.rm_rf!(root)
    end)

    {:ok, empty, _} = live(sign_in(conn), "/settings")
    assert has_element?(empty, "#upgrade-backup-status", "No upgrade copy recorded")
    id = Ecto.UUID.generate()
    directory = Path.join([root, "backups", id])
    File.mkdir_p!(directory)
    File.chmod!(Path.dirname(directory), 0o700)
    File.chmod!(directory, 0o700)
    stat = File.stat!(root)
    contents = "DATABASE_ROWS_MUST_NOT_RENDER"

    receipt = %{
      "format" => 1,
      "backup_id" => id,
      "verified_at" => "2026-10-23T12:00:00Z",
      "from_versions" => [1],
      "target_versions" => [1, 2],
      "bytes" => byte_size(contents),
      "sha256" => String.duplicate("a", 64),
      "root_device" => stat.major_device,
      "root_inode" => stat.inode
    }

    for {path, bytes} <- [
          {Path.join(directory, "foundation.db"), contents},
          {Path.join(directory, "receipt.json"), Jason.encode!(receipt)},
          {Path.join(root, "backups/latest.json"),
           Jason.encode!(%{"format" => 1, "backup_id" => id})}
        ] do
      File.write!(path, bytes)
      File.chmod!(path, 0o600)
    end

    {:ok, view, html} = live(sign_in(conn), "/settings")
    assert has_element?(view, "#upgrade-backup-status time[datetime='2026-10-23T12:00:00Z']")
    assert has_element?(view, "#upgrade-backup-details", "Schema: 1 → 2")
    assert has_element?(view, "#upgrade-backup-details", "backups/#{id}/foundation.db")
    assert has_element?(view, "#upgrade-backup-details", "does not recheck")
    refute html =~ contents
    refute has_element?(view, "#upgrade-backup-details button")
    refute has_element?(view, "#upgrade-backup-details a")
    send(view.pid, :clock)
    assert has_element?(view, "#upgrade-backup-details", "Schema: 1 → 2")

    File.write!(Path.join(directory, "receipt.json"), "{}")
    {:ok, invalid, _} = live(sign_in(conn), "/settings")
    assert has_element?(invalid, "#upgrade-backup-status", "metadata is unavailable")
    refute has_element?(invalid, "#upgrade-backup-details")
    assert {:error, {:redirect, %{to: "/locked"}}} = live(conn, "/settings")
  end
end
