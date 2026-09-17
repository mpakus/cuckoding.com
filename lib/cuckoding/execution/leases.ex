defmodule Cuckoding.Execution.Leases do
  @moduledoc """
  Owns exclusive resource leases in SQLite and keeps bearer tokens out of persistence.
  """

  import Ecto.Query

  alias Cuckoding.Correlation
  alias Cuckoding.Execution.Lease
  alias Cuckoding.Repo

  @token_bytes 32

  def acquire(resource_type, resource_id, owner_id, ttl_ms, options \\ [])

  def acquire(resource_type, resource_id, owner_id, ttl_ms, options)
      when is_binary(resource_type) and is_binary(resource_id) and is_binary(owner_id) and
             is_integer(ttl_ms) and ttl_ms > 0 do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())
    token = :crypto.strong_rand_bytes(@token_bytes) |> Base.url_encode64(padding: false)

    result =
      Repo.transaction(fn ->
        expire_resource(resource_type, resource_id, now)

        attrs = %{
          resource_type: resource_type,
          resource_id: resource_id,
          owner_id: owner_id,
          token_hash: token_hash(token),
          acquired_at: now,
          heartbeat_at: now,
          expires_at: DateTime.add(now, ttl_ms, :millisecond)
        }

        case Repo.insert(Lease.create_changeset(%Lease{}, attrs)) do
          {:ok, lease} -> lease
          {:error, changeset} -> rollback_conflict(changeset)
        end
      end)

    case result do
      {:ok, lease} ->
        emit(:acquired, lease, %{ttl_ms: ttl_ms})
        {:ok, lease, token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def acquire(_resource_type, _resource_id, _owner_id, _ttl_ms, _options),
    do: {:error, :invalid_lease}

  def heartbeat(lease_id, token, ttl_ms, options \\ [])

  def heartbeat(lease_id, token, ttl_ms, options)
      when is_binary(lease_id) and is_binary(token) and is_integer(ttl_ms) and ttl_ms > 0 do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())

    result =
      transaction_result(fn ->
        with {:ok, lease} <- authorized_lease(lease_id, token),
             :ok <- active_at(lease, now) do
          lease
          |> Lease.update_changeset(%{
            heartbeat_at: now,
            expires_at: DateTime.add(now, ttl_ms, :millisecond)
          })
          |> Repo.update()
        else
          {:expired, lease} -> expire_lease(lease, now)
          {:error, reason} -> {:error, reason}
        end
      end)

    with {:ok, lease} <- result do
      emit(:heartbeat, lease, %{kind: :heartbeat, ttl_ms: ttl_ms})
      {:ok, lease}
    end
  end

  def heartbeat(_lease_id, _token, _ttl_ms, _options), do: {:error, :invalid_lease}

  def release(lease_id, token, options \\ [])

  def release(lease_id, token, options) when is_binary(lease_id) and is_binary(token) do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())

    result =
      transaction_result(fn ->
        with {:ok, lease} <- authorized_lease(lease_id, token) do
          release_lease(lease, now)
        end
      end)

    with {:ok, lease} <- result do
      emit(:released, lease, %{})
      {:ok, lease}
    end
  end

  def release(_lease_id, _token, _options), do: {:error, :invalid_lease}

  def expire(now \\ Cuckoding.Clock.wall_now()) do
    {count, _rows} =
      Repo.update_all(
        from(lease in Lease,
          where: is_nil(lease.released_at) and lease.expires_at <= ^now
        ),
        set: [released_at: now, release_reason: "expired", updated_at: now]
      )

    Correlation.execute([:cuckoding, :lease, :expired], %{count: count}, %{})
    {:ok, count}
  end

  def extend_for_sleep_gap(gap_ms, options \\ [])

  def extend_for_sleep_gap(gap_ms, options) when is_integer(gap_ms) and gap_ms > 0 do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())
    gap_started_at = DateTime.add(now, -gap_ms, :millisecond)

    result =
      Repo.transaction(fn ->
        Repo.all(
          from(lease in Lease,
            where: is_nil(lease.released_at) and lease.expires_at > ^gap_started_at
          )
        )
        |> Enum.map(fn lease ->
          lease
          |> Lease.update_changeset(%{
            expires_at: DateTime.add(lease.expires_at, gap_ms, :millisecond)
          })
          |> Repo.update!()
        end)
      end)

    case result do
      {:ok, leases} ->
        Correlation.execute(
          [:cuckoding, :lease, :heartbeat],
          %{count: length(leases), gap_ms: gap_ms},
          %{kind: :sleep_gap}
        )

        {:ok, leases}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def extend_for_sleep_gap(_gap_ms, _options), do: {:error, :invalid_gap}

  def active_for(resource_type, resource_id, options \\ []) do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())

    Repo.one(
      from(lease in Lease,
        where:
          lease.resource_type == ^resource_type and lease.resource_id == ^resource_id and
            is_nil(lease.released_at) and lease.expires_at > ^now
      )
    )
  end

  defp authorized_lease(lease_id, token) do
    case Repo.get(Lease, lease_id) do
      nil -> {:error, :not_found}
      lease -> authorize_token(lease, token)
    end
  end

  defp authorize_token(lease, token) do
    if Plug.Crypto.secure_compare(lease.token_hash, token_hash(token)),
      do: {:ok, lease},
      else: {:error, :unauthorized}
  end

  defp active_at(%Lease{released_at: released_at}, _now) when not is_nil(released_at),
    do: {:error, :released}

  defp active_at(lease, now) do
    if DateTime.after?(lease.expires_at, now), do: :ok, else: {:expired, lease}
  end

  defp expire_resource(resource_type, resource_id, now) do
    Repo.update_all(
      from(lease in Lease,
        where:
          lease.resource_type == ^resource_type and lease.resource_id == ^resource_id and
            is_nil(lease.released_at) and lease.expires_at <= ^now
      ),
      set: [released_at: now, release_reason: "expired", updated_at: now]
    )
  end

  defp expire_lease(lease, now) do
    lease
    |> Lease.update_changeset(%{released_at: now, release_reason: "expired"})
    |> Repo.update()

    {:error, :expired}
  end

  defp release_lease(%Lease{released_at: nil} = lease, now) do
    lease
    |> Lease.update_changeset(%{released_at: now, release_reason: "released"})
    |> Repo.update()
  end

  defp release_lease(lease, _now), do: {:ok, lease}

  defp rollback_conflict(changeset) do
    if Keyword.has_key?(changeset.errors, :resource_type),
      do: Repo.rollback(:already_leased),
      else: Repo.rollback(changeset)
  end

  defp transaction_result(callback) do
    case Repo.transaction(callback) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp token_hash(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  defp emit(action, lease, measurements) do
    Correlation.execute(
      [:cuckoding, :lease, action],
      Map.put_new(measurements, :count, 1),
      %{lease_id: lease.id, resource_type: lease.resource_type, resource_id: lease.resource_id}
    )
  end
end
