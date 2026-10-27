defmodule Boss.Deliveries.Scheduling do
  @moduledoc "Persisted global worker capacity and commit-bound predicted scope admission."
  alias Boss.{Repo, Deliveries}
  @topic "boss:scheduling"

  def subscribe, do: Phoenix.PubSub.subscribe(Boss.PubSub, @topic)

  def get, do: transaction(&settings!/0)

  def set(version, capacity, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:scheduling_set, version, capacity}, 10_000)

  @doc false
  def capacity!, do: settings!().max_parallel_tasks

  @doc false
  def update(version, capacity, owned_count)
      when is_integer(version) and version >= 0 and capacity in 1..3 and
             is_integer(owned_count) and owned_count >= 0 do
    result =
      transaction(fn ->
        current = settings!()

        cond do
          current.version != version ->
            Repo.rollback(:stale_settings)

          current.max_parallel_tasks == capacity ->
            current

          owned_count > capacity or active_count!() > capacity ->
            Repo.rollback(:workers_active)

          true ->
            Repo.query!(
              "UPDATE delivery_settings SET max_parallel_tasks=?, version=version+1 WHERE id=1 AND version=?",
              [capacity, version]
            )

            settings!()
        end
      end)

    case result do
      {:ok, settings} ->
        Phoenix.PubSub.broadcast(Boss.PubSub, @topic, {:scheduling_updated, settings})

      _ ->
        :ok
    end

    result
  end

  def update(_, _, _), do: {:error, :invalid_capacity}

  @doc false
  def quarantined? do
    Repo.query!(
      "SELECT EXISTS(SELECT 1 FROM deliveries WHERE cleanup='unknown') OR EXISTS(SELECT 1 FROM agent_runs WHERE cleanup='unknown')"
    ).rows == [[1]]
  end

  @doc false
  def blockers(%Deliveries.Delivery{id: id}) do
    Repo.query!(
      "SELECT blocker_id FROM delivery_scope_conflicts WHERE delivery_id=? ORDER BY blocker_id",
      [id]
    ).rows
    |> List.flatten()
  end

  @doc false
  def claims_changed, do: Phoenix.PubSub.broadcast(Boss.PubSub, @topic, {:scope_claims_changed})

  defp settings! do
    %{rows: [[capacity, version]]} =
      Repo.query!("SELECT max_parallel_tasks, version FROM delivery_settings WHERE id=1")

    %{max_parallel_tasks: capacity, version: version}
  end

  defp active_count! do
    %{rows: [[count]]} =
      Repo.query!(
        "SELECT COUNT(*) FROM deliveries WHERE status IN ('planning','implementing','testing','reviewing','integrating')"
      )

    count
  end

  defp transaction(fun) do
    selector = Repo.get_dynamic_repo()
    pid = if is_atom(selector), do: Process.whereis(selector), else: selector

    if is_pid(pid) and Process.alive?(pid) do
      Repo.put_dynamic_repo(pid)

      try do
        Repo.transaction(fun, mode: :immediate)
      rescue
        _ in [Exqlite.Error, Ecto.ConstraintError, DBConnection.ConnectionError] ->
          {:error, :storage_error}
      catch
        :exit, _ -> {:error, :storage_error}
      after
        Repo.put_dynamic_repo(selector)
      end
    else
      {:error, :storage_error}
    end
  end
end
