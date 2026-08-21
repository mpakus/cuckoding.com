defmodule AgentDesk.Resources.Manager do
  @moduledoc """
  Transactional file, directory, glob, and named-resource leases.

  Overlap and shared/exclusive compatibility are decided here, not by a unique
  index alone.
  """

  import Ecto.Query

  alias AgentDesk.Agents.Session
  alias AgentDesk.Clock
  alias AgentDesk.Ids
  alias AgentDesk.Repo
  alias AgentDesk.Resources.Lease
  alias AgentDesk.Resources.Overlap
  alias AgentDesk.Scope

  @default_ttl 300

  @spec claim(Scope.t(), [map()], keyword()) ::
          {:ok, [Lease.t()]} | {:error, {:conflict, [map()]} | term()}
  def claim(%Scope{project: project, agent_session: %Session{} = session}, resources, opts \\ []) do
    ttl = Keyword.get(opts, :ttl_seconds, @default_ttl)
    all_or_nothing = Keyword.get(opts, :all_or_nothing, true)
    reason = Keyword.get(opts, :reason, "claim")
    now = Clock.utc_now()

    Repo.transaction(fn ->
      expire_due(project.id)
      active = active_leases(project.id)
      requested = Enum.map(resources, &normalize_request(&1, session.id))

      conflicts =
        for req <- requested,
            held <- active,
            Overlap.conflict?(req, held) do
          conflict_map(req, held)
        end

      if conflicts != [] and all_or_nothing do
        Repo.rollback({:conflict, conflicts})
      else
        insert_granted(requested, conflicts, project.id, session.id, reason, ttl, now)
      end
    end)
    |> unwrap_claim()
  end

  @spec release(Scope.t(), [Ecto.UUID.t()]) :: {:ok, [Lease.t()]} | {:error, term()}
  def release(%Scope{agent_session: %Session{} = session}, ids) when is_list(ids) do
    now = Clock.utc_now()

    Lease
    |> where([l], l.id in ^ids and l.agent_session_id == ^session.id and l.status == "active")
    |> Repo.update_all(set: [status: "released", released_at: now, updated_at: now])

    {:ok, list_owned(session.id)}
  end

  @spec renew(Scope.t(), [Ecto.UUID.t()], pos_integer()) ::
          {:ok, [Lease.t()]} | {:error, term()}
  def renew(%Scope{agent_session: %Session{} = session}, ids, ttl_seconds \\ @default_ttl) do
    now = Clock.utc_now()
    expires = DateTime.add(now, ttl_seconds, :second)

    {count, _} =
      from(l in Lease,
        where:
          l.id in ^ids and l.agent_session_id == ^session.id and l.status == "active" and
            l.expires_at > ^now
      )
      |> Repo.update_all(set: [renewed_at: now, expires_at: expires, updated_at: now])

    if count == 0 and ids != [] do
      {:error, :not_renewable}
    else
      {:ok, list_owned(session.id)}
    end
  end

  @spec expire_due(Ecto.UUID.t()) :: :ok
  def expire_due(project_id) when is_binary(project_id) do
    now = Clock.utc_now()

    from(l in Lease,
      where: l.project_id == ^project_id and l.status == "active" and l.expires_at <= ^now
    )
    |> Repo.update_all(set: [status: "expired", released_at: now, updated_at: now])

    :ok
  end

  @spec expire_session(Ecto.UUID.t()) :: :ok
  def expire_session(session_id) when is_binary(session_id) do
    now = Clock.utc_now()

    from(l in Lease, where: l.agent_session_id == ^session_id and l.status == "active")
    |> Repo.update_all(set: [status: "expired", released_at: now, updated_at: now])

    :ok
  end

  @spec list_project(Ecto.UUID.t()) :: [Lease.t()]
  def list_project(project_id) do
    expire_due(project_id)

    Lease
    |> where([l], l.project_id == ^project_id and l.status == "active")
    |> order_by([l], asc: l.resource_key)
    |> Repo.all()
  end

  @spec list_owned(Ecto.UUID.t()) :: [Lease.t()]
  def list_owned(session_id) do
    Lease
    |> where([l], l.agent_session_id == ^session_id and l.status == "active")
    |> Repo.all()
  end

  defp insert_granted(requested, conflicts, project_id, session_id, reason, ttl, now) do
    requested
    |> Enum.reject(&conflicted?(&1, conflicts))
    |> Enum.map(&insert_lease!(project_id, session_id, &1, reason, ttl, now))
  end

  defp conflicted?(req, conflicts) do
    Enum.any?(conflicts, &(&1.requested_key == req.resource_key))
  end

  defp active_leases(project_id) do
    Lease
    |> where([l], l.project_id == ^project_id and l.status == "active")
    |> Repo.all()
  end

  defp normalize_request(resource, session_id) do
    %{
      resource_type: to_string(resource[:type] || resource["type"] || "file"),
      resource_key: to_string(resource[:key] || resource["key"]),
      mode: to_string(resource[:mode] || resource["mode"] || "exclusive"),
      agent_session_id: session_id
    }
  end

  defp insert_lease!(project_id, session_id, req, reason, ttl, now) do
    %Lease{}
    |> Lease.changeset(%{
      id: Ids.generate(),
      project_id: project_id,
      agent_session_id: session_id,
      resource_type: req.resource_type,
      resource_key: req.resource_key,
      mode: req.mode,
      status: "active",
      reason: reason,
      acquired_at: now,
      renewed_at: now,
      expires_at: DateTime.add(now, ttl, :second)
    })
    |> Repo.insert!()
  end

  defp conflict_map(req, held) do
    %{
      requested_key: req.resource_key,
      held_key: held.resource_key,
      owner: %{agent_id: held.agent_session_id},
      reason: held.reason,
      expires_at: held.expires_at
    }
  end

  defp unwrap_claim({:ok, leases}), do: {:ok, leases}
  defp unwrap_claim({:error, {:conflict, conflicts}}), do: {:error, {:conflict, conflicts}}
  defp unwrap_claim({:error, reason}), do: {:error, reason}
end
