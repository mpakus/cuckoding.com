defmodule AgentDesk.Search.Supervisor do
  @moduledoc """
  Per-project search debounce. XERJ failure here must not stop the project.
  """

  use Supervisor

  alias AgentDesk.Projects.Project
  alias AgentDesk.Search.Debouncer

  def start_link(%Project{} = project) do
    Supervisor.start_link(__MODULE__, project, name: via(project.id))
  end

  def via(project_id), do: {:via, Registry, {AgentDesk.SearchSupervisorRegistry, project_id}}

  @impl true
  def init(%Project{} = project) do
    Supervisor.init([{Debouncer, project}], strategy: :one_for_one)
  end
end
