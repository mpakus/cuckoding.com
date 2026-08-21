defmodule AgentDesk.A2A.Hub do
  @moduledoc """
  Per-project A2A ticker: lease expiry, delegation expiry, and status snapshots.
  """

  use GenServer

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Snapshot
  alias AgentDesk.Projects.Project
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope

  @tick_ms 5_000

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, project, name: via(project.id))
  end

  def via(project_id), do: {:via, Registry, {AgentDesk.HubRegistry, project_id}}

  @impl true
  def init(%Project{} = project) do
    Process.send_after(self(), :tick, @tick_ms)
    {:ok, %{project: project}}
  end

  @impl true
  def handle_info(:tick, %{project: project} = state) do
    Manager.expire_due(project.id)
    A2A.expire_due_delegations(project.id)
    _ = Snapshot.write!(Scope.for_project(project))
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, state}
  end
end
