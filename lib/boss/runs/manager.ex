defmodule Boss.Runs.Manager do
  @moduledoc false
  use GenServer
  alias Boss.{Deliveries, Repo, Runs}

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    repo = Keyword.get(opts, :repo, Process.whereis(Repo))
    Repo.put_dynamic_repo(repo)
    registry = Keyword.get(opts, :registry, Boss.Runs.Active)
    :ets.new(registry, [:named_table, :protected, :set, read_concurrency: true])

    with {:ok, _} <- Runs.reconcile(), {:ok, _} <- Deliveries.reconcile() do
      {:ok,
       %{
         repo: repo,
         repo_monitor: Process.monitor(repo),
         registry: registry,
         active: nil,
         worker: Keyword.get(opts, :worker, &Boss.Runs.Worker.execute/3),
         check_worker: Keyword.get(opts, :check_worker, &Boss.Checks.Worker.execute/3),
         review_worker: Keyword.get(opts, :review_worker, &Boss.Reviews.Worker.execute/3),
         delivery_worker: Keyword.get(opts, :delivery_worker, &Boss.Deliveries.Worker.execute/3),
         integration_worker:
           Keyword.get(opts, :integration_worker, &Boss.Deliveries.IntegrationWorker.execute/3)
       }}
    else
      _ -> {:stop, :run_recovery_failed}
    end
  end

  @impl true
  def handle_call({:start, project, task, command}, _from, %{active: {_, _}} = state) do
    {:reply, Runs.replay(project, task, command), state}
  end

  def handle_call({:start, project, task, command}, _from, state) do
    launch(Runs.admit(project, task, command), state.worker, state)
  end

  def handle_call({:check, project, parent, command, text}, _from, state) do
    result = Runs.admit_check(project, parent, command, text, state.active != nil)
    launch(result, state.check_worker, state)
  end

  def handle_call({:review, project, parent, command}, _from, state) do
    result = Runs.admit_review(project, parent, command, state.active != nil)
    launch(result, state.review_worker, state)
  end

  def handle_call({:delivery_start, project, task, command, text}, from, state),
    do: handle_call({:delivery_start, project, task, command, text, "codex"}, from, state)

  def handle_call({:delivery_start, project, task, command, text, reviewer}, _from, state) do
    launch(
      Deliveries.admit(project, task, command, text, reviewer, state.active != nil),
      state.delivery_worker,
      state
    )
  end

  def handle_call({:delivery_integrate, project, id, command}, _from, state) do
    launch(
      Deliveries.admit_integration(project, id, command, state.active != nil),
      state.integration_worker,
      state
    )
  end

  defp launch({:ok, {:new, run}}, execute, state) do
    manager = self()

    worker =
      spawn_link(fn ->
        Repo.put_dynamic_repo(state.repo)
        execute.(run, state.repo, manager)
      end)

    :ets.insert(state.registry, {run.id, run.project_id, worker})
    Runs.broadcast(run)
    {:reply, {:ok, run}, %{state | active: {run, worker}}}
  end

  defp launch({:ok, {:existing, run}}, _, state), do: {:reply, {:ok, run}, state}
  defp launch(error, _, state), do: {:reply, error, state}

  @impl true
  def handle_info(
        {:delivery_finished, id, result},
        %{active: {%Deliveries.Delivery{id: id} = original, _}} = state
      ) do
    :ets.delete(state.registry, id)

    case result do
      {:ok, delivery} ->
        Deliveries.broadcast(delivery)

      _ ->
        case Deliveries.interrupt(id) do
          {:ok, delivery} -> Deliveries.broadcast(delivery)
          _ -> Deliveries.broadcast(original)
        end
    end

    {:noreply, %{state | active: nil}}
  end

  def handle_info({:EXIT, pid, _}, %{active: {%Deliveries.Delivery{} = delivery, pid}} = state) do
    :ets.delete(state.registry, delivery.id)
    Deliveries.interrupt(delivery.id)
    {:noreply, %{state | active: nil}}
  end

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
