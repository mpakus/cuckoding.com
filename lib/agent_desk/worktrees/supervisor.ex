defmodule AgentDesk.Worktrees.Supervisor do
  @moduledoc """
  Project-scoped worktree watcher.
  """

  use Supervisor

  alias AgentDesk.Projects.Project
  alias AgentDesk.Worktrees.Watcher

  def start_link(%Project{} = project) do
    Supervisor.start_link(__MODULE__, project, name: via(project.id))
  end

  def via(project_id), do: {:via, Registry, {AgentDesk.WorktreeSupervisorRegistry, project_id}}

  @impl true
  def init(%Project{} = project) do
    Supervisor.init([{Watcher, project}], strategy: :one_for_one)
  end
end
