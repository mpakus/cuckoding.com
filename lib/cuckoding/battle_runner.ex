defmodule Cuckoding.BattleRunner do
  @moduledoc "Bounded supervised stages across isolated Arenas; SQLite owns claims and receipts."
  use GenServer
  alias Cuckoding.{BattleClock, BattleExecutor, Battles}
  alias Cuckoding.Battles.{Attempt, Backoff, Capacity}

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(options) do
    {:ok, _} = Battles.recover()
    send(self(), :poll)

    {:ok,
     %{
       jobs: %{},
       cursor: nil,
       timer: nil,
       executor: Keyword.get(options, :executor, &execute/1),
       reconciler: Keyword.get(options, :reconciler, &BattleExecutor.reconcile/1)
     }}
  end

  @impl true
  def handle_info(:poll, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    :ok = BattleClock.check()
    state = dispatch(state)
    {:noreply, %{state | timer: Process.send_after(self(), :poll, 500)}}
  end

  def handle_info({ref, :settled}, %{jobs: jobs} = state) when is_map_key(jobs, ref) do
    Process.demonitor(ref, [:flush])
    send(self(), :poll)
    {:noreply, %{state | jobs: Map.delete(jobs, ref)}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{jobs: jobs} = state)
      when is_map_key(jobs, ref) do
    {_task, attempt, kind} = Map.fetch!(jobs, ref)

    if kind == :recovery,
      do:
        Battles.reconcile_recovery(
          attempt,
          failure(attempt, "reconciliation_interrupted", false)
        ),
      else: settle(attempt, failure(attempt, "worker_interrupted", false))

    send(self(), :poll)
    {:noreply, %{state | jobs: Map.delete(jobs, ref)}}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp dispatch(%{jobs: jobs} = state) when map_size(jobs) == 0 do
    if attempt = Battles.recovery_attempt() do
      task =
        Task.Supervisor.async_nolink(Cuckoding.BattleTasks, fn ->
          run_recovery(attempt, state.reconciler)
        end)

      put_job(state, {task, attempt, :recovery})
    else
      fill_slots(state)
    end
  end

  defp dispatch(state), do: fill_slots(state)

  defp fill_slots(state) do
    if map_size(state.jobs) < Capacity.limit() and not exclusive?(state.jobs) do
      busy = Enum.map(state.jobs, fn {_, {_, attempt, _}} -> attempt.battle_id end)

      case next_stage(state, busy) do
        {_, _, :stage} = job -> state |> put_job(job) |> fill_slots()
        _ -> state
      end
    else
      state
    end
  end

  defp next_stage(state, busy) do
    Battles.active()
    |> rotate(state.cursor)
    |> Enum.reject(&(&1.id in busy))
    |> Enum.filter(&(&1.state == "running" or Backoff.pending?(&1)))
    |> Enum.find_value(fn battle ->
      if not Capacity.concurrent?(battle.snapshot) and busy != [],
        do: :drain,
        else: start_stage(Battles.claim_next(battle.id), state.executor)
    end)
  end

  defp exclusive?(jobs) do
    Enum.any?(jobs, fn {_, {_, attempt, kind}} ->
      kind == :recovery or not Capacity.concurrent?(attempt.request["snapshot"])
    end)
  end

  defp put_job(state, {%Task{ref: ref}, attempt, _} = job),
    do: %{state | jobs: Map.put(state.jobs, ref, job), cursor: attempt.battle_id}

  defp rotate(battles, cursor) do
    case Enum.split_while(battles, &(&1.id != cursor)) do
      {before, [current | after_cursor]} -> after_cursor ++ before ++ [current]
      _ -> battles
    end
  end

  defp start_stage({:ok, %Attempt{} = attempt}, executor) do
    task =
      Task.Supervisor.async_nolink(Cuckoding.BattleTasks, fn ->
        run_stage(attempt, executor)
      end)

    {task, attempt, :stage}
  end

  defp start_stage(_, _), do: nil

  defp run_stage(attempt, executor) do
    :ok = BattleClock.check()

    result =
      if Battles.active_attempt?(attempt.id, attempt.claim_token),
        do: executor.(attempt),
        else: failure(attempt, "stage_not_started", true)

    :ok = BattleClock.check()
    settle(attempt, result)
    :settled
  catch
    # Task error reports must not print provider or database payloads.
    _, _ -> exit(:shutdown)
  end

  defp execute(attempt), do: BattleExecutor.execute(attempt, clock_check: &BattleClock.check/0)

  defp run_recovery(attempt, reconciler) do
    :ok = BattleClock.check()
    result = reconciler.(attempt)
    :ok = BattleClock.check()

    case Battles.reconcile_recovery(attempt, result) do
      {:error, reason} when reason in [:invalid_result, :foreign_result] ->
        Battles.reconcile_recovery(
          attempt,
          failure(attempt, "invalid_recovery_receipt", false)
        )

      other ->
        other
    end

    :settled
  catch
    _, _ -> exit(:shutdown)
  end

  defp settle(attempt, result) do
    case Battles.finish(attempt.id, attempt.claim_token, result) do
      {:error, reason} when reason in [:invalid_result, :foreign_result, :stop_pending] ->
        cleanup = reason == :stop_pending and Battles.stage_cleanup_verified?(attempt, result)
        reason = if reason == :stop_pending, do: "user_stop", else: "invalid_stage_receipt"
        receipt = failure(attempt, reason, cleanup)
        Battles.finish(attempt.id, attempt.claim_token, receipt)

      other ->
        other
    end
  end

  defp failure(attempt, reason, cleanup) do
    stopping = Battles.get(attempt.battle_id).state == "stopping"

    Map.merge(
      Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256)),
      %{
        "status" => if(stopping, do: "cancelled", else: "failed"),
        "reason" => reason,
        "cleanup_verified" => cleanup
      }
    )
  end
end
