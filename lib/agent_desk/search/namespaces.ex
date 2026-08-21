defmodule AgentDesk.Search.Namespaces do
  @moduledoc """
  Authorizes memory namespaces. Cross-project access is always denied.
  """

  import Ecto.Query

  alias AgentDesk.A2A.Participant
  alias AgentDesk.A2A.Task
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @spec allow?(Scope.t(), String.t()) :: boolean()
  def allow?(%Scope{project: project, agent_session: session}, namespace)
      when is_binary(namespace) do
    prefix = "project-" <> project.id <> "-"

    if String.starts_with?(namespace, prefix) do
      allow_rest?(session, project.id, String.trim_leading(namespace, prefix))
    else
      false
    end
  end

  def allow?(_scope, _namespace), do: false

  @spec shared(Ecto.UUID.t()) :: String.t()
  def shared(project_id), do: "project-" <> project_id <> "-shared"

  @spec agent(Ecto.UUID.t(), Ecto.UUID.t()) :: String.t()
  def agent(project_id, agent_id), do: "project-" <> project_id <> "-agent-" <> agent_id

  @spec task(Ecto.UUID.t(), Ecto.UUID.t()) :: String.t()
  def task(project_id, task_id), do: "project-" <> project_id <> "-task-" <> task_id

  defp allow_rest?(_session, _project_id, "shared"), do: true

  defp allow_rest?(%{id: id}, _project_id, "agent-" <> agent_id), do: id == agent_id

  defp allow_rest?(session, _project_id, "context-" <> context_id) do
    participant?(context_id, session.id)
  end

  defp allow_rest?(session, project_id, "task-" <> task_id) do
    case Repo.get_by(Task, id: task_id, project_id: project_id) do
      %Task{assigned_agent_id: assigned, context_id: context_id} ->
        assigned == session.id or participant?(context_id, session.id)

      nil ->
        false
    end
  end

  defp allow_rest?(_session, _project_id, _rest), do: false

  defp participant?(context_id, session_id) do
    Participant
    |> where(
      [p],
      p.context_id == ^context_id and p.agent_session_id == ^session_id and is_nil(p.left_at)
    )
    |> Repo.exists?()
  end
end
