defmodule Cuckoding.BattleWavesTest do
  use Cuckoding.DataCase
  import Cuckoding.BattleFixtures
  alias Cuckoding.{BattleExecutor, Battles, Tabulae}
  alias Cuckoding.Battles.{Attempt, Backoff, ProviderClosure, Waves}

  setup do
    fixture()
  end

  test "wave readiness waits for completed prerequisites even when a dependent comes next", ctx do
    independent = save_task(ctx.board, "Independent", [])
    battle = start(ctx.board)

    assert Enum.map(battle.snapshot["tasks"], & &1["id"]) == [
             ctx.first.id,
             ctx.second.id,
             independent.id
           ]

    {:ok, admission} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.finish(admission.id, admission.claim_token, result(admission))
    {:ok, first} = Battles.claim_next(battle.id)
    {:ok, second} = Battles.claim_next(battle.id)
    assert Enum.sort([first.task_id, second.task_id]) == Enum.sort([ctx.first.id, independent.id])
    assert Enum.find(Battles.tasks(battle.id), &(&1.task_id == ctx.second.id)).state == "pending"
  end

  test "parallel waves claim independent tasks then review a combined result before its dependent",
       ctx do
    independent = save_task(ctx.board, "Independent", [])

    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        ctx.board.arena_id,
        ctx.board.id,
        ctx.second.id,
        ctx.second.revision,
        Tabulae.content(ctx.second) |> Map.put("depends_on", [ctx.first.id, independent.id])
      )

    battle = start(ctx.board)
    assert battle.snapshot["parallelism"] == "parallel-waves-v1"
    {:ok, admission} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.finish(admission.id, admission.claim_token, result(admission))
    {:ok, first} = Battles.claim_next(battle.id)
    {:ok, second} = Battles.claim_next(battle.id)
    assert first.stage == "prepare_worktree" and second.stage == "prepare_worktree"
    assert Enum.sort([first.task_id, second.task_id]) == Enum.sort([ctx.first.id, independent.id])
    assert {:error, :busy} = Battles.claim_next(battle.id)

    for attempt <- [first, second],
        do: assert({:ok, _} = Battles.finish(attempt.id, attempt.claim_token, result(attempt)))

    completed =
      Enum.reduce_while(1..70, Battles.get(battle.id), fn _, current ->
        {next, _} = step(current)
        if next.state == "completed", do: {:halt, next}, else: {:cont, next}
      end)

    assert completed.state == "completed"
    assert Enum.all?(Battles.tasks(battle.id), &(&1.state == "completed"))
    history = Battles.attempts(battle.id)
    combined = Enum.find(history, &(&1.stage == "combine"))
    assert combined.task_id == independent.id

    refute combined.request["context"]["head"] ==
             combined.request["task_context"]["preparation"]["head"]

    review = Enum.find(history, &(&1.task_id == independent.id and &1.stage == "secutor"))
    assert review.request["task_context"]["candidate_sha"] == combined.result["candidate_sha"]

    dependent =
      Enum.find(history, &(&1.task_id == ctx.second.id and &1.stage == "prepare_worktree"))

    integrated = Enum.find(history, &(&1.task_id == independent.id and &1.stage == "integrate"))
    assert dependent.request["context"]["head"] == integrated.result["head"]
  end

  defp claim_stage(battle, stage) do
    {:ok, attempt} = Battles.claim_next(battle.id)

    if attempt.stage == stage do
      attempt
    else
      {:ok, next} = Battles.finish(attempt.id, attempt.claim_token, result(attempt))
      claim_stage(next, stage)
    end
  end

  @tag :parallel
  test "a combination conflict retains evidence and repairs through a fresh writer within review limits",
       ctx do
    save_task(ctx.board, "Independent", [])
    battle = start(ctx.board)
    attempt = claim_stage(battle, "combine")

    failure =
      Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))
      |> Map.merge(%{
        "status" => "failed",
        "reason" => "candidate_conflict",
        "cleanup_verified" => true
      })

    assert {:ok, repaired} = Battles.finish(attempt.id, attempt.claim_token, failure)
    assert repaired.state == "running"
    assert repaired.stage == "prepare_worktree"
    assert Repo.get!(Attempt, attempt.id).state == "failed"
    task = Enum.find(Battles.tasks(battle.id), &(&1.task_id == attempt.task_id))
    assert task.review_round == 1
    assert task.context["feedback"] =~ "conflict"
    assert {:ok, paused} = Battles.pause(repaired.id, repaired.control_revision)
    assert paused.state == "paused"
    assert {:ok, resumed} = Battles.resume(paused.id, paused.control_revision)
    assert {:ok, fresh} = Battles.claim_next(resumed.id)
    assert fresh.stage == "prepare_worktree" and fresh.task_id == attempt.task_id
    refute fresh.id == attempt.request["task_context"]["preparation"]["key"]
    assert fresh.request["context"]["head"] == attempt.request["context"]["head"]
    refute Battles.retry_available?(resumed)
  end

  defp wave_pair(ctx) do
    independent = save_task(ctx.board, "Independent", [])
    battle = start(ctx.board)
    {:ok, admission} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.finish(admission.id, admission.claim_token, result(admission))
    {:ok, first} = Battles.claim_next(battle.id)
    {:ok, second} = Battles.claim_next(battle.id)
    assert Enum.sort([first.task_id, second.task_id]) == Enum.sort([ctx.first.id, independent.id])
    {battle, first, second}
  end

  @tag :parallel
  test "concurrent wave claims reserve each task once without charging capacity waits", ctx do
    save_task(ctx.board, "Independent", [])
    battle = start(ctx.board)
    {:ok, admission} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.finish(admission.id, admission.claim_token, result(admission))

    claims =
      1..8
      |> Task.async_stream(fn _ -> Battles.claim_next(battle.id) end)
      |> Enum.map(&elem(&1, 1))

    accepted = for {:ok, attempt} <- claims, do: attempt
    assert length(accepted) == 2
    assert length(Enum.uniq_by(accepted, & &1.task_id)) == 2
    assert Enum.count(claims, &(&1 == {:error, :busy})) == 6
    assert Battles.get(battle.id).turns_used == 0
    assert length(Battles.attempts(battle.id)) == 3
  end

  @tag :parallel
  test "an exact shared connection queues the other lane without another attempt or turn", ctx do
    {battle, first, second} = wave_pair(ctx)

    for attempt <- [first, second],
        do: assert({:ok, _} = Battles.finish(attempt.id, attempt.claim_token, result(attempt)))

    {:ok, coordinator} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.finish(coordinator.id, coordinator.claim_token, result(coordinator))
    {:ok, busy} = Battles.claim_next(battle.id)
    assert busy.role == "speculator"
    before = Battles.attempts(battle.id)
    turns = Battles.get(battle.id).turns_used
    assert {:error, :capacity} = Battles.claim_next(battle.id)
    assert Battles.attempts(battle.id) == before
    assert Battles.get(battle.id).turns_used == turns
  end

  @tag :parallel
  test "late work rejects its sibling without changing the result context or accepting either task",
       ctx do
    {battle, first, second} = wave_pair(ctx)
    before = Battles.get(battle.id)

    assert {:error, "late_result_rejected"} =
             Battles.finish(first.id, first.claim_token, result(first), first.deadline_at)

    assert Battles.get(battle.id).context == before.context
    assert {:ok, rejected} = Battles.finish(second.id, second.claim_token, result(second))
    assert rejected.state == "needs_attention"
    assert rejected.context == before.context
    assert Repo.get!(Attempt, second.id).state == "cancelled"
    refute Battles.retry_available?(rejected)
    assert Battles.skip_preview(rejected) == []
    assert Enum.all?(Battles.tasks(battle.id), &(&1.state != "completed"))
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
  end

  defp provider_pair(ctx) do
    Cuckoding.PlanningFixtures.cursor_speculator(ctx.board)
    {battle, first, second} = wave_pair(ctx)

    for attempt <- [first, second],
        do: assert({:ok, _} = Battles.finish(attempt.id, attempt.claim_token, result(attempt)))

    {:ok, coordinator} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.finish(coordinator.id, coordinator.claim_token, result(coordinator))
    {:ok, cursor} = Battles.claim_next(battle.id)
    {:ok, codex} = Battles.claim_next(battle.id)
    assert cursor.role == "speculator" and codex.role == "summa_rudis"
    refute cursor.request["role"]["agent_id"] == codex.request["role"]["agent_id"]
    {battle, cursor, codex}
  end

  @tag :parallel
  test "restart retains both provider claims and inspects each exact closure without replay",
       ctx do
    {battle, first, second} = provider_pair(ctx)
    assert {:ok, _} = Battles.recover()
    interrupted = Enum.map([first, second], &Repo.get!(Attempt, &1.id))
    assert Enum.all?(interrupted, &(&1.state == "interrupted"))
    assert {:error, :cleanup_required} = Battles.stop(battle.id)

    for attempt <- interrupted do
      assert Battles.recovery_attempt().id == attempt.id

      native =
        ProviderClosure.binding_for(attempt)
        |> Map.take(~w(attempt_sha256 agent_id kind))
        |> Map.merge(%{
          "status" => "provider_closed",
          "request_id" => attempt.id,
          "cleanup_verified" => true,
          "pid" => 123,
          "spawned_at_ms" => 1000,
          "elapsed_ms" => 20,
          "receipt_sha256" => String.duplicate("a", 64)
        })

      observed =
        BattleExecutor.reconcile_provider(attempt, fn _, active? ->
          assert(active?.())
          native
        end)

      assert {:ok, %{state: "needs_attention"}} = Battles.reconcile_provider(attempt, observed)
      assert Repo.get!(Attempt, attempt.id) == attempt
    end

    assert Battles.recovery_attempt() == nil
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
    assert Enum.all?(Battles.tasks(battle.id), &(&1.state != "completed"))
  end

  @tag :parallel
  test "each failed lane requires its own bounded explicit Retry before work continues", ctx do
    {battle, first, second} = provider_pair(ctx)

    for {attempt, reason} <- [{first, "connection_lost"}, {second, "provider_error"}] do
      failure =
        Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))
        |> Map.merge(%{
          "status" => "failed",
          "reason" => reason,
          "cleanup_verified" => true,
          "provider" => %{"status" => reason}
        })

      assert {:ok, _} = Battles.finish(attempt.id, attempt.claim_token, failure)
    end

    blocked = Battles.get(battle.id)
    refute Map.has_key?(blocked.context, "provider_backoff")
    assert {:ok, other} = Battles.retry(blocked.id, blocked.control_revision)
    assert other.state == "needs_attention" and other.current_task_id == second.task_id
    assert {:error, :not_running} = Battles.claim_next(other.id)
    assert {:ok, ready} = Battles.retry(other.id, other.control_revision)
    assert ready.state == "running"
    assert {:ok, fresh} = Battles.claim_next(ready.id)
    assert fresh.task_id == first.task_id
    refute fresh.id in [first.id, second.id]
    assert ready.deadline_at == battle.deadline_at
    assert Enum.sort(ready.context["provider_retries"]) == Enum.sort([first.id, second.id])
  end

  @tag :parallel
  test "a settled transient failure schedules backoff after its clean sibling drains", ctx do
    {battle, first, second} = provider_pair(ctx)

    failure =
      Map.take(first.request, ~w(battle_id request_id task_id stage criteria_sha256))
      |> Map.merge(%{
        "status" => "failed",
        "reason" => "connection_lost",
        "cleanup_verified" => true,
        "provider" => %{"status" => "connection_lost"}
      })

    assert {:ok, draining} = Battles.finish(first.id, first.claim_token, failure)
    refute Map.has_key?(draining.context, "provider_backoff")
    assert {:ok, waiting} = Battles.finish(second.id, second.claim_token, result(second))
    assert waiting.context["provider_backoff"]["delay_seconds"] == 5
    {:ok, due, 0} = Backoff.due_at(waiting)
    assert {:ok, fresh} = Battles.claim_next(battle.id, due)
    assert fresh.task_id == first.task_id and fresh.id != first.id
  end

  @tag :parallel
  test "a user Pause does not turn a drained provider failure into automatic backoff", ctx do
    {battle, first, second} = provider_pair(ctx)
    assert {:ok, %{state: "pausing"}} = Battles.pause(battle.id, 0)

    failure =
      Map.take(first.request, ~w(battle_id request_id task_id stage criteria_sha256))
      |> Map.merge(%{
        "status" => "failed",
        "reason" => "connection_lost",
        "cleanup_verified" => true,
        "provider" => %{"status" => "connection_lost"}
      })

    assert {:ok, _} = Battles.finish(first.id, first.claim_token, failure)
    assert {:ok, blocked} = Battles.finish(second.id, second.claim_token, result(second))
    assert blocked.state == "needs_attention"
    refute Map.has_key?(blocked.context, "provider_backoff")
    assert {:error, :not_running} = Battles.claim_next(battle.id)
    assert Battles.retry_available?(blocked)
  end

  @tag :parallel
  test "separate Skip decisions retain both failed lanes and stop if every task is omitted",
       ctx do
    {battle, first, second} = provider_pair(ctx)

    for attempt <- [first, second] do
      receipt =
        Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))
        |> Map.merge(%{
          "status" => "failed",
          "reason" => "provider_error",
          "cleanup_verified" => true,
          "provider" => %{"status" => "provider_error"}
        })

      assert {:ok, _} = Battles.finish(attempt.id, attempt.claim_token, receipt)
    end

    blocked = Battles.get(battle.id)
    count = length(Battles.attempts(battle.id))

    assert {:ok, remaining} =
             Battles.skip(blocked.id, blocked.control_revision, first.task_id, true)

    assert remaining.state == "needs_attention" and remaining.current_task_id == second.task_id

    assert {:ok, stopped} =
             Battles.skip(remaining.id, remaining.control_revision, second.task_id, true)

    assert stopped.state == "stopped" and stopped.reason == "all_tasks_skipped"
    assert length(Battles.attempts(battle.id)) == count
    assert Enum.sort(stopped.context["skipped_attempts"]) == Enum.sort([first.id, second.id])
  end

  @tag :parallel
  test "restart retains every uncertain native claim without inferring closure from absence",
       ctx do
    {battle, first, second} = wave_pair(ctx)
    assert {:ok, _} = Battles.recover()

    for attempt <- [first, second] do
      interrupted = Repo.get!(Attempt, attempt.id)
      assert interrupted.state == "interrupted"
      assert interrupted.request == attempt.request
    end

    assert Battles.recovery_attempt().id in [first.id, second.id]
    assert Enum.all?(Battles.tasks(battle.id), &is_nil(&1.context["preparation"]))
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
  end

  @tag :parallel
  test "Pause drains both wave workers before a clean durable boundary", ctx do
    {battle, first, second} = wave_pair(ctx)
    assert {:ok, pausing} = Battles.pause(battle.id, 0)
    assert pausing.state == "pausing"
    assert {:ok, waiting} = Battles.finish(first.id, first.claim_token, result(first))
    assert waiting.state == "pausing"
    refute Waves.blocked?(waiting)
    assert {:ok, paused} = Battles.finish(second.id, second.claim_token, result(second))
    assert paused.state == "paused"
    refute Waves.blocked?(paused)
    assert paused.deadline_at == battle.deadline_at
    assert {:ok, resumed} = Battles.resume(paused.id, paused.control_revision)
    assert resumed.state == "running"
  end

  @tag :parallel
  test "a timing fence cancels every wave claim and Stop waits for every closure", ctx do
    {battle, first, second} = wave_pair(ctx)
    previous = DateTime.utc_now()
    gap = Cuckoding.BattleClock.gap({previous, 0}, {DateTime.add(previous, 10), 10_000})
    assert {:ok, [_]} = Battles.observe_timing_gap(gap)

    for attempt <- [first, second],
        do: refute(Battles.active_attempt?(attempt.id, attempt.claim_token))

    assert {:ok, %{state: "stopping"}} = Battles.stop(battle.id)
    assert {:ok, waiting} = Battles.finish(first.id, first.claim_token, result(first))
    assert waiting.state == "stopping"
    assert {:ok, stopped} = Battles.finish(second.id, second.claim_token, result(second))
    assert stopped.state == "stopped"

    assert Enum.sort(stopped.context["timing_closed_attempts"]) ==
             Enum.sort([first.id, second.id])

    assert Enum.all?(Battles.tasks(battle.id), &(&1.state != "completed"))
  end

  @tag :parallel
  test "Stop waits for both exact wave cleanup receipts", ctx do
    {battle, first, second} = wave_pair(ctx)
    assert {:ok, stopping} = Battles.stop(battle.id)
    assert stopping.state == "stopping"
    cancelled = %{"status" => "cancelled", "cleanup_verified" => true}
    assert {:ok, waiting} = Battles.finish(first.id, first.claim_token, result(first, cancelled))
    assert waiting.state == "stopping"

    assert waiting.context["cancellation_started_at"] ==
             stopping.context["cancellation_started_at"]

    {:ok, cancelled_at, 0} = DateTime.from_iso8601(stopping.context["cancellation_started_at"])
    refute Battles.idle_sleep_requested?(DateTime.add(cancelled_at, 5))

    assert {:ok, stopped} =
             Battles.finish(second.id, second.claim_token, result(second, cancelled))

    assert stopped.state == "stopped"
  end

  @tag :parallel
  test "a failed wave drains its sibling without assigning that sibling a failure", ctx do
    {battle, first, second} = wave_pair(ctx)
    failure = %{"status" => "failed", "reason" => "native_refused", "cleanup_verified" => true}
    assert {:ok, waiting} = Battles.finish(first.id, first.claim_token, result(first, failure))
    assert waiting.state == "pausing"
    assert {:error, :not_running} = Battles.claim_next(battle.id)
    assert {:ok, blocked} = Battles.finish(second.id, second.claim_token, result(second))
    assert blocked.state == "needs_attention"
    assert blocked.current_task_id == first.task_id
    assert blocked.reason == "native_refused"
    assert Map.keys(blocked.context["lane_blockers"]) == [first.task_id]
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
  end

  defp step(battle) do
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, next} = Battles.finish(attempt.id, attempt.claim_token, result(attempt))
    {next, attempt}
  end
end
