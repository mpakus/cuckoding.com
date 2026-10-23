defmodule Cuckoding.Battles.TaskBlocks do
  @moduledoc "Verified task-local attention; unresolved work never becomes completion evidence."
  alias Cuckoding.Battles.{Attempt, Receipts}
  alias Cuckoding.{Foundation, Repo}

  def policy, do: "task-local-continuation-v1"

  def enabled?(snapshot),
    do: snapshot["blocker_scope"] == policy() and snapshot["parallelism"] == "parallel-waves-v1"

  def local_task?(battle, task_id) do
    entry = get_in(battle.context, ["task_blocks", task_id])

    enabled?(battle.snapshot) and is_map(entry) and
      entry["reason"] == get_in(battle.context, ["lane_blockers", task_id])
  end

  def retain(battle, attempt) do
    reason = get_in(battle.context, ["lane_blockers", attempt.task_id])

    if enabled?(battle.snapshot) and reason in ~w(blocked review_limit) do
      retain_local(battle, Repo.get!(Attempt, attempt.id), reason)
    else
      battle
    end
  end

  defp retain_local(battle, attempt, reason) do
    if eligible?(battle, attempt, reason) do
      entry = %{"attempt_id" => attempt.id, "stage" => attempt.stage, "reason" => reason}
      entries = Map.put(battle.context["task_blocks"] || %{}, attempt.task_id, entry)
      battle = change(battle, context: Map.put(battle.context, "task_blocks", entries))

      Foundation.record("battle.task_blocked", %{
        "battle_id" => battle.id,
        "arena_id" => battle.arena_id,
        "tabula_id" => battle.tabula_id,
        "task_id" => attempt.task_id,
        "attempt_id" => attempt.id,
        "reason" => reason,
        "scope" => "task"
      })

      if battle.state == "needs_attention" and battle.context["task_block_user_pause"] == true,
        do: change(battle, state: "pausing"),
        else: battle
    else
      battle
    end
  end

  def settled?(battle, attempt) do
    entry = get_in(battle.context, ["task_blocks", attempt.task_id])

    local_task?(battle, attempt.task_id) and entry["attempt_id"] == attempt.id and
      entry["stage"] == attempt.stage and eligible?(battle, attempt, entry["reason"])
  end

  def local_only?(battle) do
    blockers = battle.context["lane_blockers"] || %{}

    enabled?(battle.snapshot) and blockers != %{} and
      Enum.all?(blockers, fn {task_id, _} ->
        id = get_in(battle.context, ["task_blocks", task_id, "attempt_id"])

        case id && Repo.get(Attempt, id) do
          %Attempt{task_id: ^task_id} = attempt -> settled?(battle, attempt)
          _ -> false
        end
      end)
  end

  defp eligible?(battle, attempt, reason) do
    not is_nil(attempt.task_id) and not is_nil(attempt.role) and
      attempt.battle_id == battle.id and attempt.request["snapshot"] == battle.snapshot and
      attempt.result["cleanup_verified"] == true and local_outcome?(attempt, reason) and
      Receipts.bound?(attempt, attempt.result) and
      Receipts.provider_valid?(attempt, attempt.result)
  end

  defp local_outcome?(%Attempt{state: "failed", result: %{"status" => "blocked"}}, "blocked"),
    do: true

  defp local_outcome?(
         %Attempt{
           state: "completed",
           stage: "secutor",
           result: %{"status" => "changes_requested"},
           request: %{
             "review_round" => round,
             "snapshot" => %{"limits" => %{"review_rounds" => limit}}
           }
         },
         "review_limit"
       )
       when is_integer(round) and is_integer(limit) and round >= 0 and limit > 0,
       do: round + 1 == limit

  defp local_outcome?(_, _), do: false

  def pause_context(battle),
    do:
      if(enabled?(battle.snapshot),
        do: Map.put(battle.context, "task_block_user_pause", true),
        else: battle.context
      )

  def resume_context(context), do: Map.delete(context, "task_block_user_pause")

  def clear(context, ids),
    do: Map.update(context, "task_blocks", %{}, &Map.drop(&1, ids))

  defp change(battle, fields), do: Repo.update!(Ecto.Changeset.change(battle, fields))
end
