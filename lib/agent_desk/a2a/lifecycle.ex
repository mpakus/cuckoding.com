defmodule AgentDesk.A2A.Lifecycle do
  @moduledoc false

  import Ecto.Query

  alias AgentDesk.A2A.Artifact
  alias AgentDesk.A2A.Delegation
  alias AgentDesk.A2A.Idempotency
  alias AgentDesk.A2A.Task
  alias AgentDesk.Agents
  alias AgentDesk.Agents.Session
  alias AgentDesk.Clock
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @spec expire_due_delegations(Ecto.UUID.t()) :: :ok
  def expire_due_delegations(project_id) do
    now = Clock.utc_now()

    from(d in Delegation,
      where:
        d.project_id == ^project_id and d.status == "proposed" and not is_nil(d.expires_at) and
          d.expires_at <= ^now
    )
    |> Repo.update_all(set: [status: "expired", updated_at: now])

    :ok
  end

  @spec revoke(Scope.t(), Ecto.UUID.t(), map()) :: {:ok, Delegation.t()} | {:error, term()}
  def revoke(%Scope{agent_session: %Session{} = session} = scope, id, attrs) do
    key = Map.fetch!(attrs, :idempotency_key)

    case Idempotency.transact(scope, "revoke_delegation", key, %{id: id}, fn ->
           transition(scope, session, id, "revoked", fn d -> d.from_agent_id == session.id end)
         end) do
      {:ok, _kind, %{"id" => id}} -> {:ok, Repo.get!(Delegation, id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec redirect(Scope.t(), Ecto.UUID.t(), map()) :: {:ok, Delegation.t()} | {:error, term()}
  def redirect(%Scope{agent_session: %Session{} = session} = scope, id, attrs) do
    key = Map.fetch!(attrs, :idempotency_key)
    to_id = Map.fetch!(attrs, :to_agent_id)

    case Idempotency.transact(scope, "redirect_delegation", key, %{id: id, to: to_id}, fn ->
           do_redirect(scope, session, id, to_id)
         end) do
      {:ok, _kind, %{"id" => id}} -> {:ok, Repo.get!(Delegation, id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec heartbeat(Scope.t(), map()) :: {:ok, Session.t()} | {:error, term()}
  def heartbeat(%Scope{agent_session: %Session{} = session}, attrs) do
    availability = Map.get(attrs, :status, session.status)

    Agents.update_session(session, %{last_heartbeat_at: Clock.utc_now()})
    |> tap(fn
      {:ok, _} -> maybe_card_availability(session, availability)
      _ -> :ok
    end)
  end

  @spec get_artifact(Scope.t(), Ecto.UUID.t()) :: {:ok, Artifact.t()} | {:error, term()}
  def get_artifact(%Scope{project: project}, id) do
    case Repo.get_by(Artifact, id: id, project_id: project.id) do
      nil -> {:error, :not_found}
      %Artifact{} = artifact -> verify_bytes(artifact)
    end
  end

  @spec update_task(Scope.t(), Task.t(), map()) :: {:ok, Task.t()} | {:error, term()}
  def update_task(%Scope{project: project} = scope, %Task{} = task, attrs) do
    with :ok <- if(task.project_id == project.id, do: :ok, else: {:error, :forbidden}),
         :ok <- AgentDesk.A2A.Graph.guard_completion(task, attrs) do
      expected = Map.get(attrs, :expected_version, task.lock_version)

      result =
        task
        |> Task.changeset(Map.take(attrs, [:status, :status_reason, :assigned_agent_id]))
        |> AgentDesk.OptimisticLock.check(expected)
        |> Repo.update()

      case result do
        {:ok, updated} ->
          _ = AgentDesk.A2A.Graph.release_ready(updated)
          _ = notify_orchestration(scope, task, updated)

          Phoenix.PubSub.broadcast(
            AgentDesk.PubSub,
            "project:" <> project.id <> ":task:" <> updated.id,
            {:task_updated, updated}
          )

          {:ok, updated}

        other ->
          other
      end
    end
  end

  defp notify_orchestration(scope, previous, updated) do
    Module.concat([AgentDesk, A2A, Orchestration]).on_task_updated(scope, previous, updated)
    :ok
  rescue
    _ -> :ok
  end

  @spec subscribe_task(Scope.t(), Ecto.UUID.t()) :: :ok
  def subscribe_task(%Scope{project: project}, task_id) do
    Phoenix.PubSub.subscribe(AgentDesk.PubSub, "project:" <> project.id <> ":task:" <> task_id)
  end

  defp transition(%Scope{project: project}, _session, id, status, allowed?) do
    delegation = Repo.get_by(Delegation, id: id, project_id: project.id)

    cond do
      is_nil(delegation) ->
        {:error, :not_found}

      not allowed?.(delegation) ->
        {:error, :forbidden}

      delegation.status != "proposed" ->
        {:error, :invalid_state}

      true ->
        {:ok, updated} =
          delegation
          |> Delegation.changeset(%{status: status, responded_at: Clock.utc_now()})
          |> Repo.update()

        {:ok, %{"id" => updated.id}}
    end
  end

  defp do_redirect(%Scope{project: project} = scope, session, id, to_id) do
    with {:ok, _to} <- Agents.get_session(scope, to_id) do
      delegation = Repo.get_by!(Delegation, id: id, project_id: project.id)

      cond do
        delegation.from_agent_id != session.id ->
          {:error, :forbidden}

        delegation.status != "proposed" ->
          {:error, :invalid_state}

        true ->
          {:ok, updated} =
            delegation
            |> Delegation.changeset(%{
              to_agent_id: to_id,
              lock_version: delegation.lock_version + 1
            })
            |> Repo.update()

          {:ok, %{"id" => updated.id}}
      end
    end
  end

  defp verify_bytes(%Artifact{} = artifact) do
    case File.read(artifact.path) do
      {:ok, bytes} ->
        hash = :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)

        if hash == artifact.sha256 do
          {:ok, artifact}
        else
          artifact |> Artifact.changeset(%{state: "corrupt"}) |> Repo.update()
          {:error, :artifact_integrity}
        end

      {:error, _} ->
        artifact |> Artifact.changeset(%{state: "missing"}) |> Repo.update()
        {:error, :missing_bytes}
    end
  end

  defp maybe_card_availability(session, status) do
    availability =
      case status do
        "working" -> "busy"
        "blocked" -> "blocked"
        "idle" -> "idle"
        _ -> nil
      end

    if availability do
      card = Repo.get_by(AgentDesk.A2A.AgentCard, agent_session_id: session.id)

      if card,
        do:
          card
          |> AgentDesk.A2A.AgentCard.changeset(%{availability: availability})
          |> Repo.update()
    end
  end
end
