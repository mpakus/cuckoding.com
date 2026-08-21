defmodule AgentDesk.Worktrees.Watcher do
  @moduledoc """
  Polls the main checkout and agent worktrees for dirty and unexpected edits.
  """

  use GenServer

  alias AgentDesk.Projects.Project
  alias AgentDesk.Worktrees

  @tick_ms 2_000

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, project, name: via(project.id))
  end

  def via(project_id), do: {:via, Registry, {AgentDesk.WorktreeRegistry, project_id}}

  @impl true
  def init(%Project{} = project) do
    Worktrees.reconcile(project)
    Process.send_after(self(), :tick, @tick_ms)
    {:ok, %{project: project}}
  end

  @impl true
  def handle_info(:tick, %{project: project} = state) do
    Worktrees.reconcile(project)
    warnings = Worktrees.unexpected_main_edits(project)

    Phoenix.PubSub.broadcast(
      AgentDesk.PubSub,
      "project:" <> project.id <> ":worktrees",
      {:worktrees_scanned, warnings}
    )

    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, state}
  end
end
