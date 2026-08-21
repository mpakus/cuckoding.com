defmodule AgentDesk.A2A.Idempotency do
  @moduledoc """
  Per-session idempotency for mutating A2A operations.
  """

  alias AgentDesk.A2A.IdempotencyRecord
  alias AgentDesk.Canonical
  alias AgentDesk.Clock
  alias AgentDesk.Ids
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @spec transact(Scope.t(), String.t(), String.t(), term(), (-> {:ok, map()} | {:error, term()})) ::
          {:ok, :fresh | :replay, map()} | {:error, :idempotency_conflict | term()}
  def transact(%Scope{project: project, agent_session: session}, operation, key, canonical, fun)
      when is_binary(operation) and is_binary(key) and is_function(fun, 0) do
    hash = Canonical.hash(canonical)

    case Repo.transaction(fn ->
           do_transact(project.id, session.id, operation, key, hash, fun)
         end) do
      {:ok, {:fresh, payload}} -> {:ok, :fresh, payload}
      {:ok, {:replay, payload}} -> {:ok, :replay, payload}
      {:error, :idempotency_conflict} -> {:error, :idempotency_conflict}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_transact(project_id, session_id, operation, key, hash, fun) do
    case Repo.get_by(IdempotencyRecord, agent_session_id: session_id, idempotency_key: key) do
      %IdempotencyRecord{request_hash: ^hash, result_status: "succeeded"} = record ->
        {:replay, record.result_payload}

      %IdempotencyRecord{} ->
        Repo.rollback(:idempotency_conflict)

      nil ->
        case fun.() do
          {:ok, payload} when is_map(payload) ->
            persist!(project_id, session_id, operation, key, hash, "succeeded", payload)
            {:fresh, payload}

          {:error, reason} ->
            Repo.rollback(reason)
        end
    end
  end

  defp persist!(project_id, session_id, operation, key, hash, status, payload) do
    ttl_hours = Keyword.fetch!(Application.fetch_env!(:agent_desk, :a2a), :idempotency_ttl_hours)
    now = Clock.utc_now()

    %IdempotencyRecord{}
    |> IdempotencyRecord.changeset(%{
      id: Ids.generate(),
      project_id: project_id,
      agent_session_id: session_id,
      idempotency_key: key,
      operation: operation,
      request_hash: hash,
      result_status: status,
      result_payload: payload,
      expires_at: DateTime.add(now, ttl_hours * 3600, :second)
    })
    |> Repo.insert!()
  end
end
