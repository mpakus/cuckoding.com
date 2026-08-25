defmodule AgentDesk.A2A.Authorization do
  @moduledoc false

  import Ecto.Query

  alias AgentDesk.A2A.Artifact
  alias AgentDesk.A2A.Context
  alias AgentDesk.A2A.Participant
  alias AgentDesk.A2A.Task
  alias AgentDesk.Agents.Session
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @active_session_statuses ~w(queued starting idle working waiting blocked)

  @spec eligible_recipient(Scope.t(), Ecto.UUID.t()) ::
          {:ok, Session.t()} | {:error, :forbidden | :not_found}
  def eligible_recipient(%Scope{project: project}, session_id) when is_binary(session_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(session_id) do
      case Repo.get_by(Session, id: session_id, project_id: project.id) do
        %Session{} = session ->
          if eligible_session?(session), do: {:ok, session}, else: {:error, :forbidden}

        nil ->
          {:error, :not_found}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  def eligible_recipient(%Scope{}, _session_id), do: {:error, :not_found}

  @spec eligible_session?(Session.t()) :: boolean()
  def eligible_session?(%Session{} = session) do
    session.status in @active_session_statuses and
      Map.get(session.settings || %{}, "tab_open", true) != false
  end

  @spec authorize_task_creation(Scope.t(), Context.t()) :: :ok | {:error, atom()}
  def authorize_task_creation(
        %Scope{project: project, agent_session: nil},
        %Context{} = context
      ) do
    same_project(project.id, context.project_id)
  end

  def authorize_task_creation(
        %Scope{project: project, agent_session: %Session{} = session},
        %Context{} = context
      ) do
    with :ok <- same_project(project.id, session.project_id),
         :ok <- same_project(project.id, context.project_id),
         {:ok, persisted_context} <- fetch_mutation_context(project.id, context.id),
         {:ok, participant} <- require_active_participant(persisted_context.id, session.id),
         true <- context_manager?(session.id, participant, persisted_context) do
      :ok
    else
      false -> {:error, :forbidden}
      {:error, _reason} = error -> error
    end
  end

  def authorize_task_creation(_scope, _context), do: {:error, :forbidden}

  @spec authorize_dependency_mutation(Scope.t(), Task.t(), Task.t()) ::
          :ok | {:error, atom()}
  def authorize_dependency_mutation(
        %Scope{project: project, agent_session: nil},
        %Task{} = task,
        %Task{} = prerequisite
      ) do
    with :ok <- same_project(project.id, task.project_id),
         :ok <- same_project(project.id, prerequisite.project_id),
         :ok <- same_context(task, prerequisite) do
      :ok
    end
  end

  def authorize_dependency_mutation(
        %Scope{project: project, agent_session: %Session{} = session},
        %Task{} = task,
        %Task{} = prerequisite
      ) do
    with :ok <- same_project(project.id, session.project_id),
         :ok <- same_project(project.id, task.project_id),
         :ok <- same_project(project.id, prerequisite.project_id),
         :ok <- same_context(task, prerequisite),
         {:ok, context} <- fetch_mutation_context(project.id, task.context_id),
         {:ok, _participant} <- require_active_participant(context.id, session.id),
         true <- dependency_manager?(session.id, task, context) do
      :ok
    else
      false -> {:error, :forbidden}
      {:error, _reason} = error -> error
    end
  end

  def authorize_dependency_mutation(_scope, _task, _prerequisite),
    do: {:error, :forbidden}

  @spec authorize_message(Scope.t(), map()) :: :ok | {:error, atom()}
  def authorize_message(
        %Scope{project: project, agent_session: %Session{} = sender},
        attrs
      ) do
    context_id = Map.get(attrs, :context_id)
    task_id = Map.get(attrs, :task_id)

    with :ok <- same_project(project.id, sender.project_id),
         {:ok, context} <- fetch_context(project.id, context_id),
         :ok <- task_in_context(project.id, context.id, task_id),
         :ok <-
           authorize_message_sender(
             Map.get(attrs, :scope, "direct"),
             context.id,
             sender.id
           ) do
      authorize_message_scope(project.id, Map.get(attrs, :scope, "direct"), attrs)
    end
  end

  def authorize_message(_scope, _attrs), do: {:error, :forbidden}

  @spec authorize_delegation_proposal(Scope.t(), Task.t()) :: :ok | {:error, atom()}
  def authorize_delegation_proposal(
        %Scope{project: project, agent_session: %Session{} = session},
        %Task{} = task
      ) do
    with :ok <- same_project(project.id, session.project_id),
         :ok <- same_project(project.id, task.project_id),
         {:ok, context} <- fetch_context(project.id, task.context_id),
         {:ok, _participant} <- require_active_participant(context.id, session.id),
         true <- task_authorized?(session.id, task, context) do
      :ok
    else
      false -> {:error, :forbidden}
      {:error, _reason} = error -> error
    end
  end

  def authorize_delegation_proposal(_scope, _task), do: {:error, :forbidden}

  @spec authorize_task_transition(Scope.t(), Task.t(), map()) :: :ok | {:error, atom()}
  def authorize_task_transition(
        %Scope{project: project, agent_session: nil},
        %Task{} = task,
        _attrs
      ) do
    same_project(project.id, task.project_id)
  end

  def authorize_task_transition(
        %Scope{project: project, agent_session: %Session{} = session},
        %Task{} = task,
        attrs
      ) do
    with :ok <- same_project(project.id, session.project_id),
         :ok <- same_project(project.id, task.project_id),
         {:ok, context} <- fetch_context(project.id, task.context_id),
         {:ok, _participant} <- require_active_participant(context.id, session.id) do
      actor = actor_permissions(session.id, task, context)

      cond do
        not actor.transition? ->
          {:error, :forbidden}

        assignment_changed?(task, attrs) and not actor.manage? ->
          {:error, :forbidden}

        true ->
          :ok
      end
    end
  end

  @spec authorize_artifact_publication(Scope.t(), map()) :: :ok | {:error, atom()}
  def authorize_artifact_publication(
        %Scope{project: project, agent_session: %Session{} = session},
        attrs
      ) do
    context_id = Map.get(attrs, :context_id)
    task_id = Map.get(attrs, :task_id)

    with :ok <- same_project(project.id, session.project_id),
         {:ok, context} <- fetch_context(project.id, context_id),
         {:ok, _participant} <- require_active_participant(context.id, session.id),
         {:ok, task} <- fetch_optional_task(project.id, context.id, task_id),
         :ok <- authorize_artifact_task(session.id, task, context),
         :ok <-
           authorize_revision(
             project.id,
             context.id,
             task_id,
             Map.get(attrs, :revision_of_id)
           ) do
      :ok
    end
  end

  def authorize_artifact_publication(_scope, _attrs), do: {:error, :forbidden}

  @spec authorize_artifact_read(Scope.t(), Artifact.t()) :: :ok | {:error, atom()}
  def authorize_artifact_read(
        %Scope{project: project, agent_session: nil},
        %Artifact{} = artifact
      ) do
    same_project(project.id, artifact.project_id)
  end

  def authorize_artifact_read(
        %Scope{project: project, agent_session: %Session{} = session},
        %Artifact{} = artifact
      ) do
    with :ok <- same_project(project.id, session.project_id),
         :ok <- same_project(project.id, artifact.project_id) do
      authorize_agent_artifact_read(session.id, artifact)
    end
  end

  def authorize_artifact_read(_scope, _artifact), do: {:error, :forbidden}

  defp authorize_message_sender(scope, context_id, sender_id)
       when scope in ["context", "task"] do
    case require_active_participant(context_id, sender_id) do
      {:ok, _participant} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp authorize_message_sender(_scope, _context_id, _sender_id), do: :ok

  defp authorize_message_scope(project_id, "direct", attrs) do
    recipient_id = Map.get(attrs, :recipient_agent_id)

    if eligible_session_in_project?(project_id, recipient_id),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp authorize_message_scope(_project_id, "task", attrs) do
    if is_binary(Map.get(attrs, :task_id)),
      do: :ok,
      else: {:error, :invalid_request}
  end

  defp authorize_message_scope(_project_id, scope, _attrs)
       when scope in ["project", "context"],
       do: :ok

  defp authorize_message_scope(_project_id, _scope, _attrs), do: {:error, :invalid_scope}

  defp actor_permissions(agent_id, task, context) do
    participant = active_participant(context.id, agent_id)
    metadata = task.metadata || %{}

    assigned? = task.assigned_agent_id == agent_id
    creator? = creator_id(metadata, context) == agent_id
    lead? = lead_id(metadata, context.metadata || %{}) == agent_id
    reviewer? = reviewer_id(metadata) == agent_id or participant_role?(participant, "reviewer")

    %{
      transition?: assigned? or creator? or lead? or reviewer?,
      manage?: creator? or lead? or reviewer?
    }
  end

  defp task_authorized?(agent_id, task, context) do
    actor_permissions(agent_id, task, context).transition?
  end

  defp context_manager?(agent_id, participant, context) do
    context.created_by_agent_id == agent_id or
      lead_id(%{}, context.metadata || %{}) == agent_id or
      participant_role?(participant, "owner") or
      participant_role?(participant, "reviewer")
  end

  defp dependency_manager?(agent_id, task, context) do
    actor = actor_permissions(agent_id, task, context)
    actor.manage? or task.assigned_agent_id == agent_id
  end

  defp authorize_artifact_task(_agent_id, nil, _context), do: :ok

  defp authorize_artifact_task(agent_id, %Task{} = task, context) do
    if task_authorized?(agent_id, task, context), do: :ok, else: {:error, :forbidden}
  end

  defp authorize_revision(_project_id, _context_id, _task_id, nil), do: :ok

  defp authorize_revision(project_id, context_id, task_id, revision_id)
       when is_binary(revision_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(revision_id) do
      case Repo.get_by(Artifact, id: revision_id, project_id: project_id) do
        %Artifact{context_id: ^context_id, task_id: ^task_id} -> :ok
        %Artifact{} -> {:error, :forbidden}
        nil -> {:error, :not_found}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  defp authorize_revision(_project_id, _context_id, _task_id, _revision_id),
    do: {:error, :invalid_request}

  defp authorize_agent_artifact_read(agent_id, %Artifact{agent_session_id: agent_id}), do: :ok

  defp authorize_agent_artifact_read(agent_id, %Artifact{} = artifact) do
    with {:ok, context} <- fetch_context(artifact.project_id, artifact.context_id),
         {:ok, task} <-
           fetch_optional_task(artifact.project_id, artifact.context_id, artifact.task_id) do
      case task do
        nil ->
          case require_active_participant(context.id, agent_id) do
            {:ok, _participant} -> :ok
            {:error, _reason} = error -> error
          end

        %Task{} ->
          authorize_artifact_task(agent_id, task, context)
      end
    end
  end

  defp fetch_context(project_id, context_id) when is_binary(context_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(context_id) do
      case Repo.get_by(Context, id: context_id, project_id: project_id) do
        %Context{} = context -> {:ok, context}
        nil -> {:error, :forbidden}
      end
    else
      :error -> {:error, :forbidden}
    end
  end

  defp fetch_context(_project_id, _context_id), do: {:error, :invalid_request}

  defp fetch_mutation_context(project_id, context_id) when is_binary(context_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(context_id) do
      case Repo.get_by(Context, id: context_id, project_id: project_id) do
        %Context{} = context -> {:ok, context}
        nil -> {:error, :not_found}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  defp fetch_mutation_context(_project_id, _context_id), do: {:error, :not_found}

  defp task_in_context(_project_id, _context_id, nil), do: :ok

  defp task_in_context(project_id, context_id, task_id) when is_binary(task_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(task_id) do
      if Repo.exists?(
           from t in Task,
             where:
               t.id == ^task_id and t.project_id == ^project_id and t.context_id == ^context_id
         ),
         do: :ok,
         else: {:error, :forbidden}
    else
      :error -> {:error, :forbidden}
    end
  end

  defp task_in_context(_project_id, _context_id, _task_id), do: {:error, :invalid_request}

  defp fetch_optional_task(_project_id, _context_id, nil), do: {:ok, nil}

  defp fetch_optional_task(project_id, context_id, task_id) when is_binary(task_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(task_id) do
      case Repo.get_by(Task, id: task_id, project_id: project_id, context_id: context_id) do
        %Task{} = task -> {:ok, task}
        nil -> {:error, :forbidden}
      end
    else
      :error -> {:error, :forbidden}
    end
  end

  defp fetch_optional_task(_project_id, _context_id, _task_id),
    do: {:error, :invalid_request}

  defp eligible_session_in_project?(project_id, session_id) when is_binary(session_id) do
    match?({:ok, _uuid}, Ecto.UUID.cast(session_id)) and
      case Repo.get_by(Session, id: session_id, project_id: project_id) do
        %Session{} = session -> eligible_session?(session)
        nil -> false
      end
  end

  defp eligible_session_in_project?(_project_id, _session_id), do: false

  defp active_participant(context_id, agent_id) do
    Participant
    |> where(
      [participant],
      participant.context_id == ^context_id and participant.agent_session_id == ^agent_id and
        is_nil(participant.left_at)
    )
    |> limit(1)
    |> Repo.one()
  end

  defp require_active_participant(context_id, agent_id) do
    case active_participant(context_id, agent_id) do
      %Participant{} = participant -> {:ok, participant}
      nil -> {:error, :forbidden}
    end
  end

  defp participant_role?(%Participant{role: actual}, expected) when actual == expected, do: true
  defp participant_role?(_participant, _role), do: false

  defp creator_id(metadata, context) do
    metadata["created_by_agent_id"] || context.created_by_agent_id
  end

  defp lead_id(metadata, context_metadata) do
    metadata["lead_agent_id"] ||
      get_in(metadata, ["orchestration", "lead_agent_id"]) ||
      context_metadata["lead_agent_id"]
  end

  defp reviewer_id(metadata), do: metadata["reviewer_id"]

  defp assignment_changed?(task, attrs) do
    case Map.fetch(attrs, :assigned_agent_id) do
      {:ok, assigned_agent_id} -> assigned_agent_id != task.assigned_agent_id
      :error -> false
    end
  end

  defp same_context(%Task{context_id: context_id}, %Task{context_id: context_id}), do: :ok
  defp same_context(_task, _prerequisite), do: {:error, :forbidden}

  defp same_project(left, right) when left == right, do: :ok
  defp same_project(_left, _right), do: {:error, :forbidden}
end
