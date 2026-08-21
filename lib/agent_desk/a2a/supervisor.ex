defmodule AgentDesk.A2A.Supervisor do
  @moduledoc """
  Project-scoped A2A processes. Started with every project runtime.
  """

  use Supervisor

  alias AgentDesk.A2A.Hub
  alias AgentDesk.Projects.Project

  def start_link(%Project{} = project) do
    Supervisor.start_link(__MODULE__, project, name: via(project.id))
  end

  def via(project_id), do: {:via, Registry, {AgentDesk.A2ASupervisorRegistry, project_id}}

  @impl true
  def init(%Project{} = project) do
    Supervisor.init([{Hub, project}], strategy: :one_for_one)
  end
end
