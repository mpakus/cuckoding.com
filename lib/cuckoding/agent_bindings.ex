defmodule Cuckoding.AgentBindings do
  @moduledoc "Explicit, audited authentication bindings without rewriting run snapshots."
  import Ecto.Query

  alias Cuckoding.Adapters
  alias Cuckoding.Adapters.ProviderAccount
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Repo

  def for_run(run_id) do
    # ponytail: one small binding event per queued edit; add a projection only if this grows.
    Repo.all(
      from event in RunEvent,
        where: event.run_id == ^run_id and event.event_type == "run.agent_connected",
        order_by: [asc: event.sequence],
        select: event.payload
    )
    |> Map.new(&{&1["role_key"], &1["provider_account_id"]})
  end

  def connect_run(run_id, role_key, account_id) do
    EventStore.transaction(fn ->
      with %Run{state: "queued"} = run <- Repo.get(Run, run_id),
           role when not is_nil(role) <-
             Enum.find(
               run.workflow_snapshot_json["roles"],
               &(&1["role_key"] == role_key and &1["role_kind"] == "agent")
             ),
           :ok <- compatible(role["adapter_key"], role["settings"] || %{}, account_id),
           {:ok, _event} <-
             EventStore.append_in_transaction(run_id, %{
               event_type: "run.agent_connected",
               public_summary: "Saved agent connected to queued role",
               payload: %{"role_key" => role_key, "provider_account_id" => account_id}
             }) do
        :connected
      else
        {:error, reason} -> Repo.rollback(reason)
        _other -> Repo.rollback(:run_not_queued_or_role_missing)
      end
    end)
  end

  def compatible(adapter, settings, %ProviderAccount{} = account) do
    case account do
      %{adapter_key: ^adapter, capabilities_json: %{"settings" => saved}} ->
        if Map.take(saved, ["executable_path", "api_key_helper"]) ==
             Map.take(settings, ["executable_path", "api_key_helper"]),
           do: :ok,
           else: {:error, :provider_account_mismatch}

      _other ->
        {:error, :provider_account_mismatch}
    end
  end

  def compatible(adapter, settings, account_id) when is_binary(account_id),
    do: compatible(adapter, settings, Adapters.get_provider_account(account_id))

  def compatible(_adapter, _settings, _account), do: {:error, :provider_account_mismatch}
end
