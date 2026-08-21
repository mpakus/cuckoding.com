defmodule AgentDesk.Search.Debouncer do
  @moduledoc false

  use GenServer

  alias AgentDesk.Projects.Project
  alias AgentDesk.Search.Indexer

  @delay_ms 1_500

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, project, name: via(project.id))
  end

  def via(project_id), do: {:via, Registry, {AgentDesk.SearchRegistry, project_id}}

  @impl true
  def init(%Project{} = project) do
    Phoenix.PubSub.subscribe(AgentDesk.PubSub, "project:" <> project.id <> ":worktrees")
    timer = Process.send_after(self(), :index, 100)
    {:ok, %{project: project, timer: timer}}
  end

  @impl true
  def handle_info({:worktrees_scanned, _warnings}, state) do
    {:noreply, schedule(state)}
  end

  def handle_info(:index, %{project: project} = state) do
    _ = Indexer.index_project(project)
    {:noreply, %{state | timer: nil}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp schedule(%{timer: timer} = state) do
    if timer, do: Process.cancel_timer(timer)
    %{state | timer: Process.send_after(self(), :index, @delay_ms)}
  end
end
