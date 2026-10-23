defmodule Cuckoding.TaskBlocksTest do
  use Cuckoding.DataCase
  import Cuckoding.BattleFixtures
  alias Cuckoding.{Battles, Foundation}
  alias Cuckoding.Battles.{Attempt, Task}

  setup do
    fixture()
  end

  defp blocking_pair(ctx, legacy \\ false) do
    independent = save_task(ctx.board, "Independent", [])
    later = save_task(ctx.board, "Later independent", [])

    battle =
      if legacy,
        do: start_legacy(ctx.board, ["blocker_scope"]),
        else: start(ctx.board)

    {:ok, admission} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.finish(admission.id, admission.claim_token, result(admission))
    {:ok, preparation} = Battles.claim_next(battle.id)
    {:ok, sibling} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.finish(preparation.id, preparation.claim_token, result(preparation))
    {:ok, coordinator} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.finish(coordinator.id, coordinator.claim_token, result(coordinator))
    {:ok, speculator} = Battles.claim_next(battle.id)
    assert speculator.stage == "speculator" and speculator.task_id == ctx.first.id
    {battle, speculator, sibling, independent, later}
  end

  defp blocked(attempt) do
    result(attempt)
    |> Map.put("status", "blocked")
    |> put_in(["provider", "report", "outcome"], "blocked")
  end

  defp run_until_attention(battle, receipt \\ &result/1) do
    Enum.reduce_while(1..150, battle, fn _, current ->
      if current.state == "running" do
        {:ok, attempt} = Battles.claim_next(current.id)
        {:ok, next} = Battles.finish(attempt.id, attempt.claim_token, receipt.(attempt))
        {:cont, next}
      else
        {:halt, current}
      end
    end)
  end

  test "a verified task blocker drains, continues independent waves and never skips its dependent",
       ctx do
    {battle, first, sibling, independent, later} = blocking_pair(ctx)
    assert battle.snapshot["blocker_scope"] == "task-local-continuation-v1"
    assert {:ok, draining} = Battles.finish(first.id, first.claim_token, blocked(first))
    assert draining.state == "pausing"
    assert {:error, :not_running} = Battles.claim_next(battle.id)
    retained = Repo.get!(Attempt, first.id)
    assert {:ok, running} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))
    assert running.state == "running"
    assert running.current_task_id == independent.id
    finished = run_until_attention(running)
    assert finished.state == "needs_attention" and finished.current_task_id == ctx.first.id
    tasks = Map.new(Battles.tasks(battle.id), &{&1.task_id, &1})
    assert tasks[independent.id].state == "completed"
    assert tasks[later.id].state == "completed"
    assert tasks[ctx.first.id].state == "needs_attention"
    assert tasks[ctx.second.id].state == "pending"
    refute Enum.any?(Battles.attempts(battle.id), &(&1.task_id == ctx.second.id))

    refute Enum.any?(
             Battles.attempts(battle.id),
             &(&1.stage in ~w(final_checks final_secutor summary))
           )

    assert Repo.get!(Attempt, first.id) == retained
    assert finished.deadline_at == battle.deadline_at
    assert finished.context["omitted_tasks"] in [nil, []]

    assert {:ok, skipped} =
             Battles.skip(finished.id, finished.control_revision, ctx.first.id, true)

    partial = run_until_attention(skipped)
    assert partial.state == "partial"
    assert Enum.find(Battles.tasks(battle.id), &(&1.task_id == ctx.second.id)).state == "deferred"
  end

  test "a blocked writer retains edits without lending them to independent candidates", ctx do
    {battle, speculator, sibling, _, _} = blocking_pair(ctx)
    {:ok, _} = Battles.finish(speculator.id, speculator.claim_token, result(speculator))
    {:ok, writer} = Battles.claim_next(battle.id)
    assert writer.stage == "implementor"
    sha = String.duplicate("d", 64)

    receipt =
      blocked(writer)
      |> put_in(["provider", "tools"], [
        %{
          "call_id" => Ecto.UUID.generate(),
          "tool" => "edit_file",
          "status" => "completed",
          "path" => "lib/work.ex",
          "sha256" => sha
        }
      ])
      |> put_in(["provider", "changes"], [%{"path" => "lib/work.ex", "sha256" => sha}])

    {:ok, _} = Battles.finish(writer.id, writer.claim_token, receipt)
    retained = Repo.get!(Attempt, writer.id)
    {:ok, running} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))
    assert running.context["head"] == writer.request["context"]["head"]
    stopped = run_until_attention(running)
    assert stopped.state == "needs_attention"

    refute Enum.any?(
             Battles.attempts(battle.id),
             &(&1.task_id == writer.task_id and &1.stage in ~w(capture integrate))
           )

    assert Repo.get!(Attempt, writer.id) == retained
    assert retained.result["provider"]["changes"] == receipt["provider"]["changes"]
  end

  test "a user Pause prevents automatic task-block continuation", ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx)
    assert {:ok, %{state: "pausing"}} = Battles.pause(battle.id, battle.control_revision)
    assert {:ok, _} = Battles.finish(first.id, first.claim_token, blocked(first))
    assert {:ok, stopped} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))
    assert stopped.state == "paused"
    assert {:error, :not_running} = Battles.claim_next(battle.id)
    assert Repo.get_by!(Task, battle_id: battle.id, task_id: sibling.task_id).state == "specs"
    assert {:ok, resumed} = Battles.resume(stopped.id, stopped.control_revision)
    assert resumed.state == "running"
    assert {:ok, next} = Battles.claim_next(battle.id)
    assert next.task_id == sibling.task_id
  end

  test "shared native failure takes priority over an earlier task blocker", ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx)
    assert {:ok, _} = Battles.finish(first.id, first.claim_token, blocked(first))
    failure = result(sibling, %{"status" => "failed", "reason" => "native_refused"})
    assert {:ok, stopped} = Battles.finish(sibling.id, sibling.claim_token, failure)
    assert stopped.state == "needs_attention" and stopped.current_task_id == sibling.task_id
    assert stopped.reason == "native_refused"
    assert stopped.context["task_blocks"][first.task_id]["attempt_id"] == first.id
    refute Battles.retry_available?(stopped)
    assert Battles.skip_preview(stopped) == []
    assert {:error, :not_running} = Battles.claim_next(battle.id)
  end

  test "uncertain cleanup and foreign receipts never establish local continuation", ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx)
    foreign = Map.put(blocked(first), "criteria_sha256", String.duplicate("f", 64))
    assert {:error, :foreign_result} = Battles.finish(first.id, first.claim_token, foreign)
    assert Repo.get!(Attempt, first.id).state == "running"
    assert Battles.get(battle.id).context["task_blocks"] == nil

    assert {:ok, _} =
             Battles.finish(
               first.id,
               first.claim_token,
               Map.put(blocked(first), "cleanup_verified", false)
             )

    assert {:ok, stopped} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))
    assert stopped.state == "needs_attention"
    assert stopped.context["task_blocks"] == nil
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    assert Battles.skip_preview(stopped) == []
  end

  test "the retained block must bind its exact attempt before the drain can continue", ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx)
    assert {:ok, draining} = Battles.finish(first.id, first.claim_token, blocked(first))
    context = put_in(draining.context, ["task_blocks", first.task_id, "attempt_id"], sibling.id)
    Repo.update!(Ecto.Changeset.change(draining, context: context))
    assert {:ok, stopped} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))
    assert stopped.state == "needs_attention"
    assert {:error, :not_running} = Battles.claim_next(battle.id)
  end

  test "binding drift closes the Arena before independent admission",
       ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx)
    assert {:ok, _} = Battles.finish(first.id, first.claim_token, blocked(first))
    workspace = Foundation.workspace()

    Repo.update!(
      Ecto.Changeset.change(workspace, codex: Map.put(workspace.codex, "status", "unsupported"))
    )

    assert {:ok, stopped} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))
    assert stopped.state == "needs_attention" and stopped.reason == "resume_binding_changed"
    assert {:error, :not_running} = Battles.claim_next(battle.id)
  end

  test "the consumed turn limit cannot be bypassed by independent continuation", ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx)
    assert {:ok, draining} = Battles.finish(first.id, first.claim_token, blocked(first))
    Repo.update!(Ecto.Changeset.change(draining, turns_used: battle.snapshot["limits"]["turns"]))
    assert {:ok, stopped} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))
    assert stopped.state == "needs_attention" and stopped.reason == "turn_limit"
    assert {:error, :not_running} = Battles.claim_next(battle.id)
  end

  test "restart pauses a settled independent checkpoint without replaying the blocked task",
       ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx)
    assert {:ok, _} = Battles.finish(first.id, first.claim_token, blocked(first))
    assert {:ok, running} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))
    retained = Repo.get!(Attempt, first.id)
    assert {:ok, _} = Battles.recover()
    paused = Battles.get(battle.id)
    assert paused.state == "paused" and paused.reason == "restart_checkpoint"
    assert paused.deadline_at == running.deadline_at
    assert paused.turns_used == running.turns_used
    assert {:error, :not_running} = Battles.claim_next(battle.id)
    assert {:ok, resumed} = Battles.resume(paused.id, paused.control_revision)
    assert {:ok, next} = Battles.claim_next(resumed.id)
    assert next.task_id == sibling.task_id
    assert Repo.get!(Attempt, first.id) == retained
    assert resumed.context["provider_retries"] in [nil, []]
  end

  test "an interrupted independent worker still requires exact cleanup proof", ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx)
    {:ok, _} = Battles.finish(first.id, first.claim_token, blocked(first))
    {:ok, _} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))
    {:ok, active} = Battles.claim_next(battle.id)
    assert {:ok, _} = Battles.recover()
    stopped = Battles.get(battle.id)
    assert stopped.state == "needs_attention" and stopped.reason == "restart_requires_inspection"
    assert Repo.get!(Attempt, active.id).state == "interrupted"
    assert Repo.get!(Attempt, first.id).state == "failed"
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    assert {:error, :not_running} = Battles.claim_next(battle.id)
    assert Battles.skip_preview(stopped) == []
    refute Battles.retry_available?(stopped)
  end

  test "separate task-local blockers each retain an explicit Skip decision", ctx do
    {battle, first, sibling, independent, later} = blocking_pair(ctx)
    {:ok, _} = Battles.finish(first.id, first.claim_token, blocked(first))
    {:ok, running} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))

    stopped =
      run_until_attention(running, fn attempt ->
        if attempt.task_id == independent.id and attempt.stage == "speculator",
          do: blocked(attempt),
          else: result(attempt)
      end)

    assert map_size(stopped.context["task_blocks"]) == 2
    assert Repo.get_by!(Task, battle_id: battle.id, task_id: later.id).state == "completed"

    assert {:ok, remaining} =
             Battles.skip(stopped.id, stopped.control_revision, first.task_id, true)

    assert remaining.state == "needs_attention" and remaining.current_task_id == independent.id
    assert map_size(remaining.context["task_blocks"]) == 1

    assert {:ok, final} =
             Battles.skip(remaining.id, remaining.control_revision, independent.id, true)

    assert run_until_attention(final).state == "partial"
  end

  test "separate Skip decisions cannot release a user Pause with multiple task blockers", ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx)
    {:ok, _} = Battles.finish(first.id, first.claim_token, blocked(first))
    {:ok, _} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))
    {:ok, coordinator} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.finish(coordinator.id, coordinator.claim_token, result(coordinator))
    {:ok, second} = Battles.claim_next(battle.id)
    current = Battles.get(battle.id)
    {:ok, _} = Battles.pause(battle.id, current.control_revision)
    {:ok, paused} = Battles.finish(second.id, second.claim_token, blocked(second))
    assert paused.state == "paused" and map_size(paused.context["task_blocks"]) == 2
    {:ok, remaining} = Battles.skip(paused.id, paused.control_revision, first.task_id, true)
    assert remaining.state == "paused" and remaining.current_task_id == second.task_id
    assert {:error, :not_running} = Battles.claim_next(battle.id)
    {:ok, ready} = Battles.skip(remaining.id, remaining.control_revision, second.task_id, true)
    assert ready.state == "paused"
    assert {:error, :not_running} = Battles.claim_next(battle.id)
    {:ok, resumed} = Battles.resume(ready.id, ready.control_revision)
    assert run_until_attention(resumed).state == "partial"
  end

  test "historical snapshots retain the original whole-wave attention behavior", ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx, true)
    assert {:ok, _} = Battles.finish(first.id, first.claim_token, blocked(first))
    assert {:ok, stopped} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))
    assert stopped.state == "needs_attention"
    assert stopped.context["task_blocks"] == nil
    assert {:error, :not_running} = Battles.claim_next(battle.id)
  end

  test "exhausted independent task review stays local without accepting its rejected candidate",
       ctx do
    independent = save_task(ctx.board, "Independent", [])
    later = save_task(ctx.board, "Later independent", [])
    battle = start(ctx.board)

    receipt = fn attempt ->
      if attempt.task_id == ctx.first.id and attempt.stage == "secutor",
        do:
          result(attempt)
          |> Map.put("status", "changes_requested")
          |> put_in(["provider", "report", "outcome"], "changes_requested"),
        else: result(attempt)
    end

    stopped = run_until_attention(battle, receipt)
    assert stopped.state == "needs_attention" and stopped.reason == "review_limit"
    tasks = Map.new(Battles.tasks(battle.id), &{&1.task_id, &1})
    assert tasks[ctx.first.id].review_round == 3
    assert tasks[ctx.first.id].state == "needs_attention"
    assert tasks[ctx.second.id].state == "pending"
    assert tasks[independent.id].state == "completed" and tasks[later.id].state == "completed"

    refute Enum.any?(
             Battles.attempts(battle.id),
             &(&1.task_id == ctx.first.id and &1.stage == "integrate")
           )

    assert stopped.context["task_blocks"][ctx.first.id]["reason"] == "review_limit"
    refute Battles.retry_available?(stopped)
    assert Battles.skip_preview(stopped) != []
  end

  test "SQLite rejects a direct claim of a blocked task under the new policy", ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx)
    assert {:ok, _} = Battles.finish(first.id, first.claim_token, blocked(first))
    assert {:ok, _} = Battles.finish(sibling.id, sibling.claim_token, result(sibling))

    assert_raise Exqlite.Error, ~r/blocked task cannot be claimed/, fn ->
      Repo.insert!(%Attempt{
        id: Ecto.UUID.generate(),
        battle_id: battle.id,
        task_id: first.task_id,
        stage: first.stage,
        role: first.role,
        request: first.request,
        claim_token: Ecto.UUID.generate(),
        state: "running",
        deadline_at: first.deadline_at
      })
    end
  end

  test "classification and receipt settlement roll back together if the audit event fails", ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx)
    before = Battles.get(battle.id)

    Repo.query!(
      "CREATE TRIGGER refuse_task_block BEFORE INSERT ON events WHEN NEW.kind='battle.task_blocked' BEGIN SELECT RAISE(ABORT, 'fixture block audit refused'); END"
    )

    assert_raise Exqlite.Error, ~r/fixture block audit refused/, fn ->
      Battles.finish(first.id, first.claim_token, blocked(first))
    end

    assert Battles.get(battle.id) == before
    assert Repo.get!(Attempt, first.id).state == "running"
    Repo.query!("DROP TRIGGER refuse_task_block")
    assert {:ok, _} = Battles.finish(first.id, first.claim_token, blocked(first))

    assert {:ok, %{state: "running"}} =
             Battles.finish(sibling.id, sibling.claim_token, result(sibling))

    assert Enum.count(Battles.evidence(battle.id), &(&1.kind == "battle.task_blocked")) == 1
  end

  test "Stop during a task-block drain never starts independent work", ctx do
    {battle, first, sibling, _, _} = blocking_pair(ctx)
    assert {:ok, _} = Battles.finish(first.id, first.claim_token, blocked(first))
    assert {:ok, %{state: "stopping"}} = Battles.stop(battle.id)
    cancelled = result(sibling, %{"status" => "cancelled", "cleanup_verified" => true})
    assert {:ok, %{state: "stopped"}} = Battles.finish(sibling.id, sibling.claim_token, cancelled)
    assert {:error, :not_running} = Battles.claim_next(battle.id)
    assert Enum.all?(Battles.tasks(battle.id), &(&1.state != "completed"))
  end

  test "the supervised asynchronous runner completes independent work around a task blocker",
       ctx do
    independent = save_task(ctx.board, "Independent", [])
    parent = self()

    executor = fn attempt ->
      send(parent, {:task_block_worker, self(), attempt.task_id})

      if attempt.stage == "speculator" and attempt.task_id == ctx.first.id,
        do: blocked(attempt),
        else: result(attempt)
    end

    start_supervised!(
      {Cuckoding.ExecutionSupervisor,
       coordinator: Cuckoding.BattleRunner,
       tasks: Cuckoding.BattleTasks,
       options: [executor: executor]}
    )

    battle = start(ctx.board)
    runner = Process.whereis(Cuckoding.BattleRunner)
    send(runner, :poll)

    await(fn ->
      current = Battles.get(battle.id)

      current.state == "needs_attention" and
        Repo.get_by!(Task, battle_id: battle.id, task_id: independent.id).state == "completed" and
        :sys.get_state(runner).jobs == %{}
    end)

    assert_receive {:task_block_worker, worker, _}
    assert worker != runner and worker != self()
    assert Elixir.Task.Supervisor.children(Cuckoding.BattleTasks) == []

    assert Repo.get_by!(Task, battle_id: battle.id, task_id: ctx.first.id).state ==
             "needs_attention"

    assert Repo.get_by!(Task, battle_id: battle.id, task_id: ctx.second.id).state == "pending"
    stop_supervised!(Cuckoding.BattleRunner)
  end

  defp await(fun, remaining \\ 500) do
    cond do
      fun.() ->
        :ok

      remaining == 0 ->
        flunk("supervised independent work did not settle")

      true ->
        Process.sleep(10)
        await(fun, remaining - 1)
    end
  end
end
