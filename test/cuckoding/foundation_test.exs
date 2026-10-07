defmodule Cuckoding.FoundationTest do
  use Cuckoding.DataCase
  alias Cuckoding.{Command, Event, Foundation, Workspace}

  test "commands are idempotent, publish only committed results and reject stale revisions" do
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    key = Ecto.UUID.generate()
    assert {:ok, command} = Foundation.discover(key, 0)
    assert command.state == "pending"
    assert_receive :updated
    assert {:ok, ^command} = Foundation.discover(key, 0)
    assert Repo.aggregate(Command, :count) == 1
    assert Repo.aggregate(Event, :count) == 1
    assert {:error, :key_conflict} = Foundation.discover(key, 1)
    assert {:ok, claim} = Foundation.claim()

    assert {:ok, %{state: "completed"}} =
             Foundation.finish(claim, %{"rtk" => %{"status" => "missing"}})

    assert Foundation.workspace().revision == 1
    assert Foundation.workspace().tools["rtk"]["status"] == "missing"
    assert {:ok, %{state: "rejected"}} = Foundation.discover(Ecto.UUID.generate(), 0)
    assert {:error, :invalid_command} = Foundation.discover("invalid", 0)
    assert Repo.aggregate(Event, :count) == 4
  end

  test "only one concurrent claimant runs; expired attempts cannot finish after reclaim" do
    {:ok, _} = Foundation.discover(Ecto.UUID.generate(), 0)

    results =
      1..5
      |> Enum.map(fn _ -> Task.async(fn -> Foundation.claim(1_000) end) end)
      |> Enum.map(&Task.await/1)

    claims = for {:ok, %Command{} = claim} <- results, do: claim
    assert [first] = claims
    assert {:ok, nil} = Foundation.claim(2_000)
    assert {:ok, recovered} = Foundation.claim(11_001)
    assert recovered.attempts == 2
    assert {:error, :lost_claim} = Foundation.finish(first, %{})
    assert {:ok, %{state: "completed"}} = Foundation.finish(recovered, %{})
  end

  test "competing revisions and exhausted claims preserve evidence" do
    {:ok, _} = Foundation.discover(Ecto.UUID.generate(), 0)
    {:ok, _} = Foundation.discover(Ecto.UUID.generate(), 0)
    {:ok, a} = Foundation.claim()
    {:ok, b} = Foundation.claim()
    assert {:ok, %{state: "completed"}} = Foundation.finish(a, %{})
    assert {:ok, %{state: "rejected"}} = Foundation.finish(b, %{"uncommitted" => %{}})
    assert Foundation.workspace().tools == %{}
    {:ok, _} = Foundation.discover(Ecto.UUID.generate(), 1)
    for time <- [1, 10_002, 20_003], do: assert({:ok, %Command{}} = Foundation.claim(time))
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    assert {:ok, %{state: "failed"}} = Foundation.claim(30_004)
    assert_receive :updated
    refute Foundation.pending?()

    assert Repo.exists?(
             from c in Command, where: c.state == "failed" and c.result == "retry_limit"
           )
  end

  test "dispatcher restarts from pending durable work" do
    pid = start_supervised!(Cuckoding.Dispatcher)
    :sys.suspend(pid)
    {:ok, _} = Foundation.discover(Ecto.UUID.generate(), 0)
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    await_revision(1)
    assert Repo.aggregate(from(c in Command, where: c.state == "completed"), :count) == 1
  end

  test "database uses required pragmas and events cannot be altered" do
    assert [[1]] = Repo.query!("PRAGMA foreign_keys").rows
    assert [["wal"]] = Repo.query!("PRAGMA journal_mode").rows
    # Exqlite installs a custom native busy handler; its timeout is not the PRAGMA value.
    assert Repo.config()[:busy_timeout] == 5_000
    Foundation.record("test.event")
    assert {:error, _} = Repo.query("UPDATE events SET kind = 'forged'")
    assert {:error, _} = Repo.query("DELETE FROM events")
    assert Repo.aggregate(Event, :count) == 1
    assert Repo.get!(Workspace, 1).revision == 0
  end

  test "a newer database refuses downgrade without changing its records" do
    Foundation.record("preserved")

    Repo.query!(
      "INSERT INTO schema_migrations(version, inserted_at) VALUES (99999999999999, CURRENT_TIMESTAMP)"
    )

    assert_raise RuntimeError, "database schema is newer than this application", fn ->
      Cuckoding.Database.init([])
    end

    assert Repo.aggregate(Event, :count) == 1

    assert [[1]] =
             Repo.query!("SELECT count(*) FROM schema_migrations WHERE version = 99999999999999").rows
  end

  defp await_revision(expected, attempts \\ 50)
  defp await_revision(_, 0), do: flunk("dispatcher did not persist completion")

  defp await_revision(expected, attempts) do
    if Foundation.workspace().revision != expected do
      Process.sleep(20)
      await_revision(expected, attempts - 1)
    end
  end
end
