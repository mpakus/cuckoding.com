defmodule Boss.Runs.Manager do
  @moduledoc false
  use GenServer
  alias Boss.{Repo, Runs}

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    repo = Keyword.get(opts, :repo, Process.whereis(Repo))
    Repo.put_dynamic_repo(repo)
    registry = Keyword.get(opts, :registry, Boss.Runs.Active)
    :ets.new(registry, [:named_table, :protected, :set, read_concurrency: true])

    with {:ok, _} <- Runs.reconcile() do
      {:ok,
       %{
         repo: repo,
         repo_monitor: Process.monitor(repo),
         registry: registry,
         active: nil,
         worker: Keyword.get(opts, :worker, &Boss.Runs.Worker.execute/3)
       }}
    else
      _ -> {:stop, :run_recovery_failed}
    end
  end

  @impl true
  def handle_call({:start, project, task, command}, _from, %{active: {run, _}} = state) do
    reply =
      if run.project_id == project and run.task_id == task and run.command_id == command,
        do: {:ok, run},
        else: {:error, :busy}

    {:reply, reply, state}
  end

  def handle_call({:start, project, task, command}, _from, state) do
    case Runs.admit(project, task, command) do
      {:ok, {:new, run}} ->
        manager = self()

        worker =
          spawn_link(fn ->
            Repo.put_dynamic_repo(state.repo)
            state.worker.(run, state.repo, manager)
          end)

        :ets.insert(state.registry, {run.id, project, worker})
        Runs.broadcast(run)
        {:reply, {:ok, run}, %{state | active: {run, worker}}}

      {:ok, {:existing, run}} ->
        {:reply, {:ok, run}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info({:run_progress, id, callback, ref, attrs}, %{active: {%{id: id}, _}} = state) do
    result = Runs.update(id, attrs)
    send(callback, {:run_progress_ack, ref})

    case result do
      {:ok, run} ->
        Runs.broadcast(run)
        {:noreply, state}

      {:error, :already_finished} ->
        {:noreply, state}

      _ ->
        send(elem(state.active, 1), :stop)
        {:stop, :run_storage_lost, state}
    end
  end

  def handle_info({:run_finished, id, result}, %{active: {%{id: id} = original, _}} = state) do
    :ets.delete(state.registry, id)

    case result do
      {:ok, run} ->
        Runs.broadcast(run)

      _ ->
        case Runs.update(id,
               status: "interrupted",
               cleanup: "unknown",
               reason:
                 "The final storage outcome is unknown. Workspace retained; no automatic restart.",
               finished_at: DateTime.utc_now()
             ) do
          {:ok, saved} -> Runs.broadcast(saved)
          _ -> Runs.broadcast(original)
        end
    end

    {:noreply, %{state | active: nil}}
  end

  def handle_info({:EXIT, pid, _}, %{active: {run, pid}} = state) do
    :ets.delete(state.registry, run.id)

    case Runs.update(run.id,
           status: "interrupted",
           cleanup: "unknown",
           reason: "Run owner stopped without a final receipt. Workspace retained.",
           finished_at: DateTime.utc_now()
         ) do
      {:ok, saved} -> Runs.broadcast(saved)
      _ -> Runs.broadcast(run)
    end

    {:noreply, %{state | active: nil}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{repo_monitor: ref} = state),
    do: {:stop, :run_storage_lost, state}

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, %{active: {_, worker}}), do: Process.exit(worker, :kill)
  def terminate(_, _), do: :ok

  @impl true
  def format_status(status), do: Map.merge(status, %{state: :redacted, message: :redacted})
end
