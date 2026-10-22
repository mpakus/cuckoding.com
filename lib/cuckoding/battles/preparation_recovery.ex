defmodule Cuckoding.Battles.PreparationRecovery do
  @moduledoc "Exact retained writer-preparation evidence; workflow transitions stay in Battles."
  alias Cuckoding.{ArenaGit, LocalGit}
  alias Cuckoding.Battles.{Attempt, Receipts}
  @envelope ~w(battle_id request_id task_id stage criteria_sha256)

  def policy, do: "retained-preparation-v1"
  def enabled?(snapshot), do: snapshot["worktree_recovery"] == policy()
  def wave_policy, do: "retained-preparation-wave-v1"

  def wave_eligible?(battle, attempts),
    do:
      battle.snapshot["worktree_wave_recovery"] == wave_policy() and
        battle.snapshot["parallelism"] == "parallel-waves-v1" and length(attempts) == 2 and
        Enum.all?(attempts, &eligible?(battle, &1))

  def member?(battle, %Attempt{stage: "prepare_worktree", role: nil} = attempt),
    do:
      not is_nil(attempt.task_id) and attempt.battle_id == battle.id and
        attempt.request["snapshot"] == battle.snapshot

  def member?(_, _), do: false

  def eligible?(battle, attempt),
    do:
      enabled?(battle.snapshot) and battle.state in ~w(running pausing) and
        member?(battle, attempt)

  def pending?(battle, %Attempt{stage: "prepare_worktree", role: nil} = attempt),
    do:
      enabled?(battle.snapshot) and battle.state == "needs_attention" and
        battle.context["preparation_recovery_pending"] == attempt.id and
        battle.id == attempt.battle_id and battle.current_task_id == attempt.task_id and
        battle.stage == attempt.stage and attempt.request["snapshot"] == battle.snapshot and
        wave_current?(battle, attempt)

  def pending?(_, _), do: false

  defp wave_current?(battle, attempt) do
    case battle.context["preparation_recovery_wave"] do
      nil ->
        true

      %{"attempt_ids" => [first, second] = ids, "remaining_ids" => [current | _] = remaining} ->
        battle.snapshot["worktree_wave_recovery"] == wave_policy() and first != second and
          current == attempt.id and remaining in [ids, [second]]

      _ ->
        false
    end
  end

  def verified?(
        %Attempt{} = attempt,
        %{"status" => "prepared", "cleanup_verified" => true, "preparation" => preparation} =
          result
      )
      when is_map(preparation) do
    receipt = Map.put(preparation, "status", "prepared")

    enabled?(attempt.request["snapshot"]) and Receipts.bound?(attempt, result) and
      Map.keys(result) -- (@envelope ++ ~w(status cleanup_verified preparation)) == [] and
      LocalGit.normalize(receipt) == receipt and
      preparation["key"] == attempt.id and
      preparation["head"] == attempt.request["context"]["head"] and
      preparation["path"] == ArenaGit.worktree_path(attempt.id)
  end

  def verified?(_, _), do: false

  def failed?(attempt, result),
    do:
      result["status"] == "failed" and result["cleanup_verified"] == false and
        Map.keys(result) -- (@envelope ++ ~w(status reason cleanup_verified)) == [] and
        Receipts.payload_valid?(attempt, result)

  def reconciled?(battle, attempt),
    do:
      enabled?(battle.snapshot) and attempt.stage == "prepare_worktree" and
        attempt.state == "interrupted" and
        verified?(
          attempt,
          get_in(battle.context, ["preparation_reconciliations", attempt.id, "receipt"])
        )
end
