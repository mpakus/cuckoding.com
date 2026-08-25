defmodule AgentDesk.Providers.ProjectSupervisor do
  @moduledoc """
  Dynamic supervisor for provider sessions belonging to one project.

  Session workers are temporary children: a provider crash is durable session
  state to reconcile or explicitly resume, not a process to restart blindly.
  """

  use DynamicSupervisor

  alias AgentDesk.Projects.Project

  @spec start_link(Project.t()) :: Supervisor.on_start()
  def start_link(%Project{} = project) do
    DynamicSupervisor.start_link(__MODULE__, project, name: via(project.id))
  end

  @spec via(Ecto.UUID.t()) :: {:via, module(), {module(), Ecto.UUID.t()}}
  def via(project_id) when is_binary(project_id) do
    {:via, Registry, {AgentDesk.ProviderSupervisorRegistry, project_id}}
  end

  @spec fetch(Ecto.UUID.t()) :: {:ok, pid()} | {:error, :not_started}
  def fetch(project_id) when is_binary(project_id) do
    case Registry.lookup(AgentDesk.ProviderSupervisorRegistry, project_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_started}
    end
  end

  @impl true
  def init(%Project{}) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
