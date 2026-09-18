defmodule Cuckoding.UpdatesTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Repo
  alias Cuckoding.Updates
  alias Cuckoding.Updates.Attempt
  alias Cuckoding.Updates.Event

  test "prepares, installs, and marks a snapshotted update healthy" do
    root = temporary_directory()
    pending = Path.join(root, "pending-update.json")

    snapshot = fn id, metadata, _options ->
      send(self(), {:snapshotted, id, metadata})

      {:ok,
       %{
         path: Path.join(root, id),
         manifest_hash: String.duplicate("a", 64),
         files: 3
       }}
    end

    assert {:ok, prepared} =
             Updates.prepare("0.2.0", true,
               current_version: "0.1.0",
               policy: fn -> :ok end,
               snapshot: snapshot,
               pending_path: pending
             )

    assert prepared.state == "prepared"
    assert prepared.schema_change
    assert_receive {:snapshotted, id, %{"active_run_ids" => []}}
    assert id == prepared.id
    assert File.stat!(pending).mode |> Bitwise.band(0o077) == 0

    assert {:ok, installing} = Updates.mark_installing(prepared.id)
    assert installing.state == "installing"
    assert {:ok, healthy} = Updates.mark_healthy_pending(pending_path: pending)
    assert healthy.state == "healthy"
    refute File.exists?(pending)

    assert Repo.aggregate(Attempt, :count, :id) == 1
    assert Repo.aggregate(Event, :count, :id) == 4
  end

  test "fails closed before snapshot for invalid versions or unsafe hibernation" do
    assert {:error, :invalid_update_version} =
             Updates.prepare("0.1.0", true,
               current_version: "0.1.0",
               policy: fn -> :ok end
             )

    assert {:error, :cannot_hibernate} =
             Updates.prepare("0.2.0", true,
               current_version: "0.1.0",
               policy: fn -> {:error, :cannot_hibernate} end
             )

    assert Repo.aggregate(Attempt, :count, :id) == 0
  end

  test "records snapshot failure without pretending the update is prepared" do
    snapshot = fn _id, _metadata, _options -> {:error, :disk_full} end

    assert {:error, :disk_full} =
             Updates.prepare("0.2.0", false,
               current_version: "0.1.0",
               policy: fn -> :ok end,
               snapshot: snapshot,
               pending_path: Path.join(temporary_directory(), "pending.json")
             )

    attempt = Repo.one!(Attempt)
    assert attempt.state == "failed"
    assert attempt.failure_reason =~ "disk_full"
    assert Repo.aggregate(Event, :count, :id) == 2
  end

  test "records a pre-install failure and clears only its pending marker" do
    root = temporary_directory()
    pending = Path.join(root, "pending.json")

    snapshot = fn id, _metadata, _options ->
      {:ok, %{path: Path.join(root, id), manifest_hash: String.duplicate("b", 64), files: 1}}
    end

    assert {:ok, prepared} =
             Updates.prepare("0.2.0", false,
               current_version: "0.1.0",
               policy: fn -> :ok end,
               snapshot: snapshot,
               pending_path: pending
             )

    assert {:ok, failed} =
             Updates.mark_failed(prepared.id, "application_backup_failed", pending_path: pending)

    assert failed.state == "failed"
    assert failed.failure_reason == "application_backup_failed"
    refute File.exists?(pending)

    assert {:ok, same} = Updates.mark_failed(prepared.id, "ignored_retry", pending_path: pending)
    assert same.id == failed.id
    assert Repo.aggregate(Event, :count, :id) == 3
  end

  defp temporary_directory do
    directory =
      Path.join(System.tmp_dir!(), "cuckoding-updates-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    directory
  end
end
