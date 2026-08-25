defmodule AgentDesk.A2A do
  @moduledoc """
  Provider-neutral internal A2A domain.

  Agents reach this module through the Agent Hub MCP surface; LiveView and
  tests may also call it with a `Scope`.
  """

  import Ecto.Query

  alias AgentDesk.A2A.AgentCard
  alias AgentDesk.A2A.Artifact
  alias AgentDesk.A2A.ArtifactFile
  alias AgentDesk.A2A.Authorization
  alias AgentDesk.A2A.Context
  alias AgentDesk.A2A.Delegation
  alias AgentDesk.A2A.Delivery
  alias AgentDesk.A2A.Directory
  alias AgentDesk.A2A.Idempotency
  alias AgentDesk.A2A.Lifecycle
  alias AgentDesk.A2A.Message
  alias AgentDesk.A2A.Messaging
  alias AgentDesk.A2A.Participant
  alias AgentDesk.A2A.Policy
  alias AgentDesk.A2A.Task
  alias AgentDesk.Agents.Session
  alias AgentDesk.Clock
  alias AgentDesk.Correlation
  alias AgentDesk.Events
  alias AgentDesk.Ids
  alias AgentDesk.OptimisticLock
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @spec register_card(Scope.t(), map()) :: {:ok, AgentCard.t()} | {:error, term()}
  def register_card(%Scope{project: project, agent_session: %Session{} = session} = scope, attrs) do
    with :ok <- same_project(scope) do
      now = Clock.utc_now()

      case Repo.get_by(AgentCard, agent_session_id: session.id) do
        nil ->
          insert_card(project.id, session.id, attrs, 1, now)

        %AgentCard{} = card ->
          card
          |> AgentCard.changeset(%{
            name: Map.get(attrs, :name, card.name),
            description: Map.get(attrs, :description, card.description),
            skills: Map.get(attrs, :skills, card.skills),
            input_modes: Map.get(attrs, :input_modes, card.input_modes),
            output_modes: Map.get(attrs, :output_modes, card.output_modes),
            features: Map.get(attrs, :features, card.features),
            availability: Map.get(attrs, :availability, card.availability),
            revision: card.revision + 1,
            published_at: now
          })
          |> Repo.update()
      end
    end
  end

  @spec create_context(Scope.t(), map()) :: {:ok, Context.t()} | {:error, term()}
  def create_context(%Scope{project: project} = scope, attrs) do
    now = Clock.utc_now()
    session_id = Scope.agent_id(scope)

    Repo.transaction(fn ->
      case insert_context(project.id, session_id, attrs) do
        {:ok, context} ->
          maybe_join_owner!(context, session_id, now)
          context

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @spec create_task(Scope.t(), Context.t(), map()) :: {:ok, Task.t()} | {:error, term()}
  def create_task(%Scope{project: project} = scope, %Context{} = context, attrs) do
    with :ok <- context_in_project(context, project),
         :ok <- Authorization.authorize_task_creation(scope, context),
         {:ok, task} <- insert_task(scope, context, attrs),
         :ok <- link_dependencies(scope, task, dependency_ids(attrs)) do
      {:ok, Repo.get!(Task, task.id)}
    end
  end

  @spec ensure_working_context(Scope.t()) :: {:ok, Context.t()} | {:error, term()}
  def ensure_working_context(%Scope{project: project} = scope) do
    case latest_context(project.id) do
      %Context{} = context -> {:ok, context}
      nil -> create_context(scope, %{title: "Workspace"})
    end
  end

  @spec propose_delegation(Scope.t(), map()) :: {:ok, Delegation.t()} | {:error, term()}
  def propose_delegation(%Scope{agent_session: %Session{} = from} = scope, attrs) do
    key = Map.fetch!(attrs, :idempotency_key)
    canonical = Map.take(attrs, [:task_id, :to_agent_id, :reason])

    case Idempotency.transact(scope, "propose_delegation", key, canonical, fn ->
           do_propose_delegation(scope, from, attrs, key)
         end) do
      {:ok, _kind, %{"id" => id}} -> {:ok, Repo.get!(Delegation, id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec accept_delegation(Scope.t(), Ecto.UUID.t(), map()) ::
          {:ok, Delegation.t()} | {:error, term()}
  def accept_delegation(%Scope{agent_session: %Session{} = session} = scope, delegation_id, attrs) do
    key = Map.fetch!(attrs, :idempotency_key)
    expected = Map.fetch!(attrs, :expected_version)
    canonical = %{delegation_id: delegation_id, decision: "accepted", expected_version: expected}

    case Idempotency.transact(scope, "accept_delegation", key, canonical, fn ->
           do_decide_delegation(scope, session, delegation_id, expected, "accepted", attrs)
         end) do
      {:ok, _kind, %{"id" => id}} -> {:ok, Repo.get!(Delegation, id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec reject_delegation(Scope.t(), Ecto.UUID.t(), map()) ::
          {:ok, Delegation.t()} | {:error, term()}
  def reject_delegation(%Scope{agent_session: %Session{} = session} = scope, delegation_id, attrs) do
    key = Map.fetch!(attrs, :idempotency_key)
    expected = Map.fetch!(attrs, :expected_version)
    canonical = %{delegation_id: delegation_id, decision: "rejected", expected_version: expected}

    case Idempotency.transact(scope, "reject_delegation", key, canonical, fn ->
           do_decide_delegation(scope, session, delegation_id, expected, "rejected", attrs)
         end) do
      {:ok, _kind, %{"id" => id}} -> {:ok, Repo.get!(Delegation, id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec send_direct_message(Scope.t(), map()) :: {:ok, Message.t()} | {:error, term()}
  def send_direct_message(scope, attrs) do
    Messaging.send(scope, Map.put_new(attrs, :scope, "direct"))
  end

  @spec send_message(Scope.t(), map()) :: {:ok, Message.t()} | {:error, term()}
  defdelegate send_message(scope, attrs), to: Messaging, as: :send

  @spec broadcast(Scope.t(), map()) :: {:ok, Message.t()} | {:error, term()}
  def broadcast(scope, attrs), do: Messaging.send(scope, Map.put(attrs, :scope, "project"))

  @spec inbox(Scope.t()) :: [Delivery.t()]
  def inbox(scope), do: Messaging.inbox(scope, 0)

  @spec inbox(Scope.t(), integer()) :: [Delivery.t()]
  def inbox(scope, cursor), do: Messaging.inbox(scope, cursor)

  defdelegate list_agents(scope), to: Directory
  defdelegate get_agent(scope, agent_id), to: Directory
  defdelegate find_agents(scope, opts \\ []), to: Directory
  defdelegate revoke_delegation(scope, id, attrs), to: Lifecycle, as: :revoke
  defdelegate redirect_delegation(scope, id, attrs), to: Lifecycle, as: :redirect
  defdelegate heartbeat(scope, attrs \\ %{}), to: Lifecycle
  defdelegate get_artifact(scope, id), to: Lifecycle
  defdelegate update_task(scope, task, attrs), to: Lifecycle
  defdelegate subscribe_task(scope, task_id), to: Lifecycle
  defdelegate expire_due_delegations(project_id), to: Lifecycle

  @spec reconcile_project(Ecto.UUID.t()) :: :ok
  def reconcile_project(project_id) when is_binary(project_id) do
    now = Clock.utc_now()
    interrupted_reason = "interrupted by project restart"
    uncertain_reason = "delivery injection outcome uncertain after project restart"

    interrupted_sessions =
      from(s in Session,
        where: s.project_id == ^project_id and s.status == "interrupted",
        select: s.id
      )

    from(t in Task,
      where:
        t.project_id == ^project_id and
          t.assigned_agent_id in subquery(interrupted_sessions) and
          t.status in [
            "queued",
            "assigned",
            "working",
            "input_required",
            "auth_required",
            "blocked",
            "review"
          ] and
          (is_nil(t.status_reason) or t.status_reason != ^interrupted_reason)
    )
    |> Repo.update_all(
      set: [status: "blocked", status_reason: interrupted_reason, updated_at: now],
      inc: [lock_version: 1]
    )

    project_messages =
      from(m in Message, where: m.project_id == ^project_id, select: m.id)

    from(d in Delivery,
      where:
        d.message_id in subquery(project_messages) and
          d.agent_session_id in subquery(interrupted_sessions) and
          d.state == "injected" and
          is_nil(d.acknowledged_at)
    )
    |> Repo.update_all(set: [state: "pending", last_error: uncertain_reason, updated_at: now])

    :ok
  end

  @spec list_delegations(Scope.t()) :: [Delegation.t()]
  def list_delegations(%Scope{project: project}) do
    Delegation
    |> where([d], d.project_id == ^project.id)
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  @spec list_tasks(Scope.t()) :: [Task.t()]
  def list_tasks(%Scope{project: project}) do
    Task
    |> where([t], t.project_id == ^project.id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @spec list_messages(Scope.t()) :: [Message.t()]
  def list_messages(%Scope{project: project}) do
    Message
    |> where([m], m.project_id == ^project.id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(50)
    |> Repo.all()
  end

  @spec list_deliveries(Scope.t()) :: [Delivery.t()]
  @spec list_deliveries(Scope.t()) :: [Delivery.t()]
  def list_deliveries(%Scope{project: project}) do
    Delivery
    |> join(:inner, [d], s in Session, on: s.id == d.agent_session_id)
    |> where([_d, s], s.project_id == ^project.id)
    |> order_by([d], desc: d.updated_at)
    |> limit(80)
    |> preload(:message)
    |> Repo.all()
  end

  def list_artifacts(%Scope{project: project}) do
    Artifact
    |> where([a], a.project_id == ^project.id)
    |> Repo.all()
  end

  @spec acknowledge(Scope.t(), Ecto.UUID.t()) :: {:ok, Delivery.t()} | {:error, term()}
  def acknowledge(%Scope{agent_session: %Session{} = session}, delivery_id) do
    case Repo.get_by(Delivery, id: delivery_id, agent_session_id: session.id) do
      nil ->
        {:error, :not_found}

      %Delivery{state: "acknowledged"} = delivery ->
        {:ok, delivery}

      %Delivery{} = delivery ->
        now = Clock.utc_now()

        delivery
        |> Delivery.changeset(%{state: "acknowledged", acknowledged_at: now})
        |> Repo.update()
    end
  end

  @spec publish_artifact(Scope.t(), map()) :: {:ok, Artifact.t()} | {:error, term()}
  def publish_artifact(%Scope{project: project, agent_session: session} = scope, attrs) do
    changeset =
      Artifact.changeset(%Artifact{}, %{
        id: Ids.generate(),
        project_id: project.id,
        context_id: Map.fetch!(attrs, :context_id),
        task_id: Map.get(attrs, :task_id),
        agent_session_id: session && session.id,
        kind: Map.fetch!(attrs, :kind),
        name: Map.fetch!(attrs, :name),
        mime_type: Map.fetch!(attrs, :mime_type),
        path: Map.fetch!(attrs, :path),
        sha256: Map.fetch!(attrs, :sha256),
        size_bytes: Map.fetch!(attrs, :size_bytes),
        state: "available",
        revision_of_id: Map.get(attrs, :revision_of_id),
        metadata: Map.get(attrs, :metadata, %{})
      })

    with :ok <- same_project(scope),
         :ok <- Authorization.authorize_artifact_publication(scope, attrs),
         :ok <- valid_artifact_changeset(changeset),
         {:ok, file_attrs} <-
           ArtifactFile.validate_publication(
             scope,
             Map.fetch!(attrs, :path),
             Map.fetch!(attrs, :size_bytes),
             Map.fetch!(attrs, :sha256)
           ) do
      changeset
      |> Ecto.Changeset.change(file_attrs)
      |> Repo.insert()
    end
  end

  defp valid_artifact_changeset(%Ecto.Changeset{valid?: true}), do: :ok
  defp valid_artifact_changeset(%Ecto.Changeset{} = changeset), do: {:error, changeset}

  defp insert_card(project_id, session_id, attrs, revision, now) do
    %AgentCard{}
    |> AgentCard.changeset(%{
      id: Ids.generate(),
      project_id: project_id,
      agent_session_id: session_id,
      revision: revision,
      name: Map.fetch!(attrs, :name),
      description: Map.get(attrs, :description, ""),
      skills: Map.get(attrs, :skills, []),
      input_modes: Map.get(attrs, :input_modes, []),
      output_modes: Map.get(attrs, :output_modes, []),
      features: Map.get(attrs, :features, %{}),
      availability: Map.get(attrs, :availability, "idle"),
      published_at: now
    })
    |> Repo.insert()
  end

  defp do_propose_delegation(%Scope{project: project} = scope, from, attrs, key) do
    with {:ok, to} <- Authorization.eligible_recipient(scope, Map.fetch!(attrs, :to_agent_id)),
         {:ok, task} <- fetch_task(project.id, Map.fetch!(attrs, :task_id)),
         :ok <- Authorization.authorize_delegation_proposal(scope, task),
         :ok <- Policy.check_delegation(project.id, from.id, task) do
      correlation =
        Correlation.new(
          context_id: task.context_id,
          idempotency_key: key
        )

      {:ok, delegation} =
        %Delegation{}
        |> Delegation.changeset(%{
          id: Ids.generate(),
          project_id: project.id,
          context_id: task.context_id,
          task_id: task.id,
          from_agent_id: from.id,
          to_agent_id: to.id,
          status: "proposed",
          reason: Map.fetch!(attrs, :reason),
          idempotency_key: key,
          lock_version: 1,
          expires_at: Map.get(attrs, :expires_at)
        })
        |> Repo.insert()

      {:ok, _} =
        Events.append(
          Map.merge(
            %{
              project_id: project.id,
              agent_session_id: from.id,
              task_id: task.id,
              type: "a2a.delegation.proposed",
              source: "a2a",
              payload: %{"delegation_id" => delegation.id, "to_agent_id" => to.id}
            },
            Correlation.to_event_attrs(correlation)
          )
        )

      {:ok, %{"id" => delegation.id}}
    end
  end

  defp do_decide_delegation(
         %Scope{project: project},
         session,
         delegation_id,
         expected,
         decision,
         attrs
       ) do
    with {:ok, _recipient} <-
           Authorization.eligible_recipient(Scope.for_agent(project, session), session.id),
         {:ok, delegation} <- fetch_delegation(project.id, delegation_id) do
      cond do
        delegation.to_agent_id != session.id ->
          {:error, :forbidden}

        delegation.status != "proposed" ->
          {:error, :invalid_state}

        true ->
          now = Clock.utc_now()

          delegation_cs =
            delegation
            |> Delegation.changeset(%{
              status: decision,
              response_reason: Map.get(attrs, :response_reason),
              responded_at: now
            })
            |> OptimisticLock.check(expected)

          with {:ok, delegation} <- Repo.update(delegation_cs),
               :ok <- maybe_assign_task(delegation, decision) do
            {:ok, _} =
              Events.append(%{
                project_id: project.id,
                agent_session_id: session.id,
                task_id: delegation.task_id,
                context_id: delegation.context_id,
                type: "a2a.delegation.#{decision}",
                source: "a2a",
                payload: %{"delegation_id" => delegation.id}
              })

            {:ok, %{"id" => delegation.id}}
          end
      end
    end
  end

  defp insert_context(project_id, session_id, attrs) do
    created_by = if session_id, do: "agent", else: "user"

    %Context{}
    |> Context.changeset(%{
      id: Ids.generate(),
      project_id: project_id,
      title: Map.get(attrs, :title),
      status: "active",
      created_by_type: created_by,
      created_by_agent_id: session_id,
      metadata: Map.get(attrs, :metadata, %{})
    })
    |> Repo.insert()
  end

  defp maybe_join_owner!(_context, nil, _now), do: :ok

  defp maybe_join_owner!(context, session_id, now) do
    %Participant{}
    |> Participant.changeset(%{
      id: Ids.generate(),
      context_id: context.id,
      agent_session_id: session_id,
      role: "owner",
      joined_at: now
    })
    |> Repo.insert!()

    :ok
  end

  defp maybe_assign_task(_delegation, "rejected"), do: :ok

  defp maybe_assign_task(%Delegation{} = delegation, "accepted") do
    case assign_task(delegation) do
      {:ok, _task} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp assign_task(%Delegation{} = delegation) do
    now = Clock.utc_now()

    {updated_count, _} =
      Task
      |> where(
        [task],
        task.id == ^delegation.task_id and task.project_id == ^delegation.project_id and
          task.context_id == ^delegation.context_id and is_nil(task.assigned_agent_id)
      )
      |> Repo.update_all(
        set: [
          status: "assigned",
          assigned_agent_id: delegation.to_agent_id,
          updated_at: now
        ],
        inc: [lock_version: 1]
      )

    case updated_count do
      1 ->
        with :ok <- ensure_active_participant(delegation, now) do
          {:ok, Repo.get!(Task, delegation.task_id)}
        end

      0 ->
        {:error, :task_conflict}
    end
  end

  defp ensure_active_participant(delegation, now) do
    active? =
      Participant
      |> where(
        [participant],
        participant.context_id == ^delegation.context_id and
          participant.agent_session_id == ^delegation.to_agent_id and
          is_nil(participant.left_at)
      )
      |> Repo.exists?()

    if active? do
      :ok
    else
      %Participant{}
      |> Participant.changeset(%{
        id: Ids.generate(),
        context_id: delegation.context_id,
        agent_session_id: delegation.to_agent_id,
        role: "participant",
        joined_at: now
      })
      |> Repo.insert()
      |> case do
        {:ok, _participant} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp fetch_task(project_id, task_id) when is_binary(task_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(task_id) do
      case Repo.get_by(Task, id: task_id, project_id: project_id) do
        %Task{} = task -> {:ok, task}
        nil -> {:error, :not_found}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  defp fetch_task(_project_id, _task_id), do: {:error, :not_found}

  defp fetch_delegation(project_id, delegation_id) when is_binary(delegation_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(delegation_id) do
      case Repo.get_by(Delegation, id: delegation_id, project_id: project_id) do
        %Delegation{} = delegation -> {:ok, delegation}
        nil -> {:error, :not_found}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  defp fetch_delegation(_project_id, _delegation_id), do: {:error, :not_found}

  defp same_project(%Scope{project: project, agent_session: %Session{project_id: project_id}}) do
    if project.id == project_id, do: :ok, else: {:error, :forbidden}
  end

  defp same_project(%Scope{agent_session: nil}), do: {:error, :forbidden}

  defp context_in_project(%Context{project_id: project_id}, %{id: project_id}), do: :ok
  defp context_in_project(_context, _project), do: {:error, :forbidden}

  defp created_by_type(%Scope{agent_session: nil}), do: "user"
  defp created_by_type(%Scope{}), do: "agent"

  defp insert_task(scope, context, attrs) do
    title = Map.get(attrs, :title) || Map.get(attrs, "title")

    %Task{}
    |> Task.changeset(%{
      id: Ids.generate(),
      project_id: scope.project.id,
      context_id: context.id,
      parent_task_id: Map.get(attrs, :parent_task_id) || Map.get(attrs, "parent_task_id"),
      title: title,
      description: Map.get(attrs, :description) || Map.get(attrs, "description") || "",
      status: "queued",
      created_by: created_by_type(scope),
      lock_version: 1,
      metadata: task_metadata(scope, attrs)
    })
    |> Repo.insert()
  end

  defp task_metadata(scope, attrs) do
    metadata = Map.get(attrs, :metadata) || Map.get(attrs, "metadata") || %{}

    case Scope.agent_id(scope) do
      agent_id when is_binary(agent_id) -> Map.put(metadata, "created_by_agent_id", agent_id)
      nil -> metadata
    end
  end

  defp link_dependencies(_scope, _task, []), do: :ok

  defp link_dependencies(scope, task, ids) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case AgentDesk.A2A.Graph.add_dependency(scope, task.id, id) do
        {:ok, _edge} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp dependency_ids(attrs) do
    attrs
    |> Map.get(:depends_on, Map.get(attrs, "depends_on", []))
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
  end

  defp latest_context(project_id) do
    Context
    |> where([c], c.project_id == ^project_id)
    |> order_by([c], desc: c.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
end
