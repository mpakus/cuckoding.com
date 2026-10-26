defmodule Boss.Projects.SpecWatcher do
  @moduledoc "Sequential automatic spec refresh, paced from completion of each sweep."
  use GenServer
  alias Boss.{Projects, Repo}
  alias Boss.Projects.SpecImporter
  require Logger

  def start_link(opts \\ []) do
    interval =
      Keyword.get(opts, :interval_ms, Application.get_env(:boss, :spec_poll_interval_ms, 2000))

    settle = Keyword.get(opts, :settle_ms, 300)

    if is_integer(interval) and interval > 0 and is_integer(settle) and settle in 0..1000 do
      GenServer.start_link(
        __MODULE__,
        %{
          interval: interval,
          settle: settle,
          repo: Keyword.get(opts, :repo, Repo),
          task: nil,
          timer: nil,
          statuses: %{}
        },
        name: __MODULE__
      )
    else
      {:error, :invalid_timing_options}
    end
  end

  def subscribe(project_id), do: Phoenix.PubSub.subscribe(Boss.PubSub, topic(project_id))
  def status(project_id), do: call_if_running({:status, project_id}, nil)
  def report(project_id, result), do: call_if_running({:report, project_id, result}, :ok)

  @impl true
  def init(state) do
    Process.flag(:trap_exit, true)
    send(self(), :sweep)
    {:ok, state}
  end

  @impl true
  def handle_call({:status, id}, _from, state), do: {:reply, Map.get(state.statuses, id), state}

  def handle_call({:report, id, result}, _from, state) do
    # Equal counts can describe different edits; only repeated failures are redundant.
    if match?({:error, _}, result) and Map.get(state.statuses, id) == result do
      {:reply, :ok, state}
    else
      Phoenix.PubSub.broadcast(Boss.PubSub, topic(id), {:spec_sync, id, result})
      {:reply, :ok, %{state | statuses: Map.put(state.statuses, id, result)}}
    end
  end

  @impl true
  def handle_info(:sweep, %{task: nil} = state) do
    # Resolve once: an old sweep must never find a replacement Repo by its name.
    repo = if is_atom(state.repo), do: Process.whereis(state.repo), else: state.repo
    settle = state.settle
    task = Task.async(fn -> sweep(repo, settle) end)
    {:noreply, %{state | task: task, timer: nil}}
  end

  def handle_info(:sweep, state), do: {:noreply, state}

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    if result != :ok, do: warn_retry()
    {:noreply, schedule(state)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %Task{ref: ref}} = state) do
    warn_retry()
    {:noreply, schedule(state)}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    if state.task, do: Task.shutdown(state.task, :brutal_kill)
    :ok
  end

  defp sweep(repo, settle) when is_pid(repo) do
    Repo.put_dynamic_repo(repo)

    Enum.each(Projects.list_projects(), fn project ->
      SpecImporter.sync(project.id, settle_ms: settle)
    end)
  rescue
    _ -> :unavailable
  catch
    :exit, _ -> :unavailable
  end

  defp sweep(_, _), do: :unavailable

  defp schedule(state) do
    %{state | task: nil, timer: Process.send_after(self(), :sweep, state.interval)}
  end

  defp warn_retry,
    do:
      Logger.warning("Automatic spec sweep could not complete; retrying after the poll interval.")

  defp topic(id), do: "specs:#{id}"

  defp call_if_running(message, fallback) do
    case Process.whereis(__MODULE__) do
      nil -> fallback
      pid -> GenServer.call(pid, message)
    end
  catch
    :exit, _ -> fallback
  end
end
