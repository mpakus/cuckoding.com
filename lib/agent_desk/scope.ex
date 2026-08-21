defmodule AgentDesk.Scope do
  @moduledoc """
  Authorization boundary for local project and agent-session operations.

  AgentDesk is a single-user desktop app; the scope is a project plus an
  optional authenticated agent session, not a cloud user account.
  """

  alias AgentDesk.Agents.Session
  alias AgentDesk.Projects.Project

  @enforce_keys [:project]
  defstruct [:project, :agent_session]

  @type t :: %__MODULE__{
          project: Project.t(),
          agent_session: Session.t() | nil
        }

  @spec for_project(Project.t()) :: t()
  def for_project(%Project{} = project), do: %__MODULE__{project: project}

  @spec for_agent(Project.t(), Session.t()) :: t()
  def for_agent(%Project{} = project, %Session{} = session) do
    %__MODULE__{project: project, agent_session: session}
  end

  @spec agent_id(t()) :: Ecto.UUID.t() | nil
  def agent_id(%__MODULE__{agent_session: nil}), do: nil
  def agent_id(%__MODULE__{agent_session: %Session{id: id}}), do: id
end
