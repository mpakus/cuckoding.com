defmodule Boss.Runs.Manager do
  @moduledoc false
  use GenServer
  alias Boss.{Deliveries, Repo, Runs}
  alias Boss.Deliveries.Queue

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    repo = Keyword.get(opts, :repo, Process.whereis(Repo))
    Repo.put_dynamic_repo(repo)
    registry = Keyword.get(opts, :registry, Boss.Runs.Active)
    :ets.new(registry, [:named_table, :protected, :set, read_concurrency: true])

    with {:ok, _} <- Runs.reconcile(),
         {:ok, _} <- Deliveries.reconcile(),
         {:ok, _} <- Queue.pause() do
      {:ok,
       %{
         repo: repo,
         repo_monitor: Process.monitor(repo),
         registry: registry,
         active: %{},
         finished: %{},
         queue_timer: nil,
         queue_cursor: nil,
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
  def handle_call({:start, project, task, command}, _from, state) when map_size(state.active) > 0,
    do: {:reply, Runs.replay(project, task, command), state}

  def handle_call({:start, project, task, command}, _from, state),
    do: launch(Runs.admit(project, task, command), state.worker, state)

  def handle_call({:check, project, parent, command, text}, _from, state),
    do:
      launch(
        Runs.admit_check(project, parent, command, text, map_size(state.active) > 0),
        state.check_worker,
        state
      )

  def handle_call({:review, project, parent, command}, _from, state),
    do:
      launch(
        Runs.admit_review(project, parent, command, map_size(state.active) > 0),
        state.review_worker,
        state
      )

  def handle_call({:delivery_start, project, task, command, text}, from, state),
    do: handle_call({:delivery_start, project, task, command, text, "codex"}, from, state)

  def handle_call({:delivery_start, project, task, command, text, reviewer}, _from, state),
    do:
      launch(
        Deliveries.admit(project, task, command, text, reviewer, managed_locked?(state)),
        state.delivery_worker,
        state
      )

  def handle_call({:delivery_integrate, project, id, command}, _from, state),
    do:
      launch(
        Deliveries.admit_integration(project, id, command, map_size(state.active) > 0),
        state.integration_worker,
        state
      )

  def handle_call({:queue_enqueue, project, task, command, text, reviewer}, _from, state) do
    result = Queue.admit(project, task, command, text, reviewer)
    queue_reply(result, state)
  end

  def handle_call({:queue_resume, project, id}, _from, state),
    do: queue_reply(Queue.resume_saved(project, id), state)

  defp queue_reply({:error, :storage_error} = result, state),
    do: {:stop, :run_storage_lost, result, state}

  defp queue_reply({:ok, _} = result, state), do: {:reply, result, schedule(state, 0)}
  defp queue_reply(result, state), do: {:reply, result, state}

  defp launch({:ok, {:new, run}}, execute, state),
    do: {:reply, {:ok, run}, start_worker(run, execute, state)}

  defp launch({:ok, {:existing, run}}, _, state), do: {:reply, {:ok, run}, state}

  defp launch({:error, :storage_error} = error, _, state),
    do: {:stop, :run_storage_lost, error, state}

  defp launch(error, _, state), do: {:reply, error, state}

  defp start_worker(run, execute, state) do
    manager = self()

    worker =
      spawn_link(fn ->
        Repo.put_dynamic_repo(state.repo)
        execute.(run, state.repo, manager)
      end)

    :ets.insert(state.registry, {run.id, run.project_id, worker})
    Runs.broadcast(run)
    %{state | active: Map.put(state.active, run.id, {run, worker})}
  end

  defp managed_locked?(state) do
    map_size(state.active) >= 2 or
      Enum.any?(state.active, fn
        {_, {%Deliveries.Delivery{status: status}, _}} -> status == "integrating"
        _ -> true
      end)
  end

  @impl true
  def handle_info({:queue_tick, tag}, %{queue_timer: {_, tag}} = state) do
    state = %{state | queue_timer: nil}
    requests = Queue.queued()
    {before, after_cursor} = Enum.split_while(requests, &(&1.id != state.queue_cursor))

    ordered =
      case after_cursor do
        [cursor | rest] -> rest ++ before ++ [cursor]
        [] -> requests
      end

    deadline = System.monotonic_time(:millisecond) + 1_000

    result =
      Enum.reduce_while(ordered, {:ok, state}, fn request, {:ok, state} ->
        if System.monotonic_time(:millisecond) >= deadline or managed_locked?(state) do
          {:halt, {:ok, state}}
        else
          state = %{state | queue_cursor: request.id}

          case Queue.claim(request.id) do
            {:ok, {:started, saved, delivery}} ->
              Runs.broadcast(saved)
              {:cont, {:ok, start_worker(delivery, state.delivery_worker, state)}}

            {:ok, {:stale, saved}} ->
              Runs.broadcast(saved)
              {:cont, {:ok, state}}

            {:error, :storage_error} ->
              {:halt, {:error, state}}

            _ ->
              {:cont, {:ok, state}}
          end
        end
      end)

    case result do
      {:ok, state} -> {:noreply, if(requests == [], do: state, else: schedule(state, 500))}
      {:error, state} -> {:stop, :run_storage_lost, state}
    end
  end

  def handle_info({kind, id, pid, result}, state)
      when kind in [:delivery_finished, :run_finished] do
    case Map.get(state.active, id) do
      {run, ^pid} ->
        expected =
          if match?(%Deliveries.Delivery{}, run), do: :delivery_finished, else: :run_finished

        cond do
          kind != expected -> {:noreply, state}
          result == {:error, :storage_error} -> {:stop, :run_storage_lost, state}
          true -> {:noreply, %{state | finished: Map.put_new(state.finished, id, result)}}
        end

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:run_progress, id, owner, callback, ref, attrs}, state) do
    case Map.get(state.active, id) do
      {%Runs.Run{}, ^owner} ->
        result = Runs.update(id, attrs)
        send(callback, {:run_progress_ack, ref})

        case result do
          {:ok, run} ->
            Runs.broadcast(run)
            {:noreply, state}

          {:error, :already_finished} ->
            {:noreply, state}

          _ ->
            {:stop, :run_storage_lost, state}
        end

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, pid, _}, state) do
    case Enum.find(state.active, fn {_, {_, worker}} -> worker == pid end) do
      {id, {run, ^pid}} -> finish(run, Map.get(state.finished, id, {:error, :owner_lost}), state)
      _ -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{repo_monitor: ref} = state),
    do: {:stop, :run_storage_lost, state}

  def handle_info(_, state), do: {:noreply, state}

  defp finish(original, result, state) do
    saved =
      case result do
        {:ok, %{id: id} = run} when id == original.id -> {:ok, run}
        _ -> interrupt(original)
      end

    case saved do
      {:ok, run} ->
        Runs.broadcast(run)
        :ets.delete(state.registry, original.id)

        {:noreply,
         schedule(
           %{
             state
             | active: Map.delete(state.active, original.id),
               finished: Map.delete(state.finished, original.id)
           },
           0
         )}

      _ ->
        {:stop, :run_storage_lost, state}
    end
  end

  defp interrupt(%Deliveries.Delivery{id: id}), do: Deliveries.interrupt(id)

  defp interrupt(run),
    do:
      Runs.update(run.id,
        status: "interrupted",
        cleanup: "unknown",
        reason: "Run owner stopped without a final receipt. Workspace retained.",
        finished_at: DateTime.utc_now()
      )

  defp schedule(state, delay) do
    if state.queue_timer, do: Process.cancel_timer(elem(state.queue_timer, 0))
    tag = make_ref()
    timer = Process.send_after(self(), {:queue_tick, tag}, delay)
    %{state | queue_timer: {timer, tag}}
  end

  @impl true
  def terminate(_, state) do
    Enum.each(state.active, fn {_, {_, worker}} -> Process.exit(worker, :kill) end)
  end

  @impl true
  def format_status(status), do: Map.merge(status, %{state: :redacted, message: :redacted})
end
