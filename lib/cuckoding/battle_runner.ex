defmodule Cuckoding.BattleRunner do
  @moduledoc "One supervised stage at a time; SQLite claims and receipts own battle progress."
  use GenServer
  alias Cuckoding.{BattleClock, BattleExecutor, Battles}
  alias Cuckoding.Battles.Attempt

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(options) do
    {:ok, _} = Battles.recover()
    send(self(), :poll)

    {:ok,
     %{
       job: nil,
       executor: Keyword.get(options, :executor, &execute/1),
       reconciler: Keyword.get(options, :reconciler, &BattleExecutor.reconcile_integration/1)
     }}
  end

  @impl true
  def handle_info(:poll, %{job: nil} = state) do
    :ok = BattleClock.check()

    job =
      if attempt = Battles.recovery_attempt() do
        task =
          Task.Supervisor.async_nolink(Cuckoding.BattleTasks, fn ->
            run_recovery(attempt, state.reconciler)
          end)

        {task, attempt, :recovery}
      else
        Enum.find_value(Battles.active(), fn battle ->
          start_stage(Battles.claim_next(battle.id), state.executor)
        end)
      end

    if is_nil(job), do: Process.send_after(self(), :poll, 500)
    {:noreply, %{state | job: job}}
  end

  def handle_info({ref, :settled}, %{job: {%Task{ref: ref}, _attempt}} = state) do
    Process.demonitor(ref, [:flush])
    send(self(), :poll)
    {:noreply, %{state | job: nil}}
  end

  def handle_info({ref, :settled}, %{job: {%Task{ref: ref}, _attempt, :recovery}} = state) do
    Process.demonitor(ref, [:flush])
    send(self(), :poll)
    {:noreply, %{state | job: nil}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{job: {%Task{ref: ref}, attempt}} = state) do
    settle(attempt, failure(attempt, "worker_interrupted", false))
    send(self(), :poll)
    {:noreply, %{state | job: nil}}
  end

  def handle_info(
        {:DOWN, ref, :process, _, _},
        %{job: {%Task{ref: ref}, attempt, :recovery}} = state
      ) do
    Battles.reconcile_integration(attempt, failure(attempt, "reconciliation_interrupted", false))
    send(self(), :poll)
    {:noreply, %{state | job: nil}}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp start_stage({:ok, %Attempt{} = attempt}, executor) do
    task =
      Task.Supervisor.async_nolink(Cuckoding.BattleTasks, fn ->
        run_stage(attempt, executor)
      end)

    {task, attempt}
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

    case Battles.reconcile_integration(attempt, result) do
      {:error, reason} when reason in [:invalid_result, :foreign_result] ->
        Battles.reconcile_integration(
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
