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

  @spec request_rebuild(Ecto.UUID.t()) :: :ok | {:error, :not_started}
  def request_rebuild(project_id) when is_binary(project_id) do
    case Registry.lookup(AgentDesk.SearchRegistry, project_id) do
      [{pid, _value}] ->
        GenServer.cast(pid, :rebuild)
        :ok

      [] ->
        {:error, :not_started}
    end
  end

  @impl true
  def init(%Project{} = project) do
    Phoenix.PubSub.subscribe(AgentDesk.PubSub, "project:" <> project.id <> ":worktrees")
    {:ok, schedule(%{project: project, timer: nil, mode: :index}, 100)}
  end

  @impl true
  def handle_cast(:rebuild, state) do
    {:noreply, schedule(%{state | mode: :rebuild}, 0)}
  end

  @impl true
  def handle_info({:worktrees_scanned, _warnings}, state) do
    {:noreply, schedule(state)}
  end

  def handle_info(
        {:index, token},
        %{project: project, timer: {_timer, token}, mode: :rebuild} = state
      ) do
    _ = Indexer.rebuild(project)
    {:noreply, %{state | timer: nil, mode: :index}}
  end

  def handle_info({:index, token}, %{project: project, timer: {_timer, token}} = state) do
    _ = Indexer.index_project(project)
    {:noreply, %{state | timer: nil}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{timer: timer}) do
    cancel_timer(timer)
    :ok
  end

  defp schedule(state, delay \\ @delay_ms) do
    cancel_timer(state.timer)
    token = make_ref()
    timer = Process.send_after(self(), {:index, token}, delay)
    %{state | timer: {timer, token}}
  end

  defp cancel_timer({timer, _token}), do: Process.cancel_timer(timer)
  defp cancel_timer(nil), do: false
end
