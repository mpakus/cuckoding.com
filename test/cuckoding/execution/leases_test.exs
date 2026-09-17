defmodule Cuckoding.Execution.LeasesTest do
  use Cuckoding.DataCase, async: false
  use ExUnitProperties

  alias Cuckoding.Execution.Lease
  alias Cuckoding.Execution.Leases

  @now ~U[2026-09-17 19:50:00.000000Z]

  property "an expired lease can be acquired by a new owner" do
    check all(ttl_ms <- integer(1..10_000), max_runs: 30) do
      resource_id = Ecto.UUID.generate()

      assert {:ok, first, token} =
               Leases.acquire("run", resource_id, "owner-1", ttl_ms, now: @now)

      assert first.token_hash != token
      assert byte_size(first.token_hash) == 64

      assert {:error, :already_leased} =
               Leases.acquire("run", resource_id, "owner-2", ttl_ms, now: @now)

      after_expiry = DateTime.add(@now, ttl_ms, :millisecond)

      assert {:ok, second, _token} =
               Leases.acquire("run", resource_id, "owner-2", ttl_ms, now: after_expiry)

      assert second.owner_id == "owner-2"
      assert Repo.get!(Lease, first.id).release_reason == "expired"
      assert Leases.active_for("run", resource_id, now: after_expiry).id == second.id
    end
  end

  property "a reported sleep gap extends leases before expiry" do
    check all(
            ttl_ms <- integer(1..5_000),
            gap_ms <- integer(5_001..60_000),
            max_runs: 20
          ) do
      resource_id = Ecto.UUID.generate()
      wake_at = DateTime.add(@now, gap_ms, :millisecond)

      assert {:ok, lease, _token} =
               Leases.acquire("run", resource_id, "owner", ttl_ms, now: @now)

      assert {:ok, extended_leases} = Leases.extend_for_sleep_gap(gap_ms, now: wake_at)
      extended = Enum.find(extended_leases, &(&1.id == lease.id))
      assert extended
      assert DateTime.after?(extended.expires_at, wake_at)
      assert {:ok, _expired_count} = Leases.expire(wake_at)
      assert Leases.active_for("run", resource_id, now: wake_at).id == lease.id
    end
  end

  test "heartbeats require the bearer token and release is idempotent" do
    assert {:ok, lease, token} = Leases.acquire("port", "4100", "run-1", 1_000, now: @now)
    assert {:error, :unauthorized} = Leases.heartbeat(lease.id, "wrong", 2_000, now: @now)

    heartbeat_at = DateTime.add(@now, 500, :millisecond)
    assert {:ok, renewed} = Leases.heartbeat(lease.id, token, 2_000, now: heartbeat_at)
    assert renewed.heartbeat_at == heartbeat_at
    assert renewed.expires_at == DateTime.add(heartbeat_at, 2_000, :millisecond)

    assert {:ok, released} = Leases.release(lease.id, token, now: heartbeat_at)
    assert released.release_reason == "released"
    assert {:ok, ^released} = Leases.release(lease.id, token, now: heartbeat_at)
    refute Leases.active_for("port", "4100", now: heartbeat_at)
  end

  test "an expired heartbeat closes the stale lease" do
    assert {:ok, lease, token} = Leases.acquire("run", "expired", "owner", 100, now: @now)
    expired_at = DateTime.add(@now, 100, :millisecond)

    assert {:error, :expired} = Leases.heartbeat(lease.id, token, 100, now: expired_at)
    assert Repo.get!(Lease, lease.id).release_reason == "expired"
  end

  test "sleep-gap telemetry carries its kind and correlation" do
    handler_id = {__MODULE__, make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:cuckoding, :lease, :heartbeat],
        fn event, measurements, metadata, _config ->
          send(test_pid, {event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    Cuckoding.Correlation.put("correlation-0103")
    assert {:ok, _lease, _token} = Leases.acquire("run", "sleep", "owner", 1_000, now: @now)

    assert {:ok, extended_leases} =
             Leases.extend_for_sleep_gap(5_000,
               now: DateTime.add(@now, 5_000, :millisecond)
             )

    assert Enum.any?(extended_leases, &(&1.resource_id == "sleep"))

    assert_receive {[:cuckoding, :lease, :heartbeat], %{gap_ms: 5_000}, metadata}
    assert metadata.kind == :sleep_gap
    assert metadata.correlation_id == "correlation-0103"
  end

  test "a lease expired before a sleep gap is not extended" do
    assert {:ok, lease, _token} = Leases.acquire("run", "stale", "owner", 1_000, now: @now)
    wake_at = DateTime.add(@now, 10_000, :millisecond)

    assert {:ok, []} = Leases.extend_for_sleep_gap(5_000, now: wake_at)
    assert {:ok, 1} = Leases.expire(wake_at)
    assert Repo.get!(Lease, lease.id).release_reason == "expired"
  end
end
