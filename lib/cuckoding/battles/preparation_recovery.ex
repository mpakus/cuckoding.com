defmodule Cuckoding.Battles.PreparationRecovery do
  @moduledoc "Exact retained writer-preparation evidence; workflow transitions stay in Battles."
  alias Cuckoding.{ArenaGit, LocalGit}
  alias Cuckoding.Battles.{Attempt, Receipts}
  @envelope ~w(battle_id request_id task_id stage criteria_sha256)

  def policy, do: "retained-preparation-v1"
  def enabled?(snapshot), do: snapshot["worktree_recovery"] == policy()

  def eligible?(battle, attempt),
    do:
      enabled?(battle.snapshot) and battle.state in ~w(running pausing) and
        attempt.stage == "prepare_worktree" and is_nil(attempt.role) and
        not is_nil(attempt.task_id) and attempt.request["snapshot"] == battle.snapshot

  def pending?(battle, %Attempt{stage: "prepare_worktree", role: nil} = attempt),
    do:
      enabled?(battle.snapshot) and battle.state == "needs_attention" and
        battle.context["preparation_recovery_pending"] == attempt.id and
        battle.id == attempt.battle_id and battle.current_task_id == attempt.task_id and
        battle.stage == attempt.stage and attempt.request["snapshot"] == battle.snapshot

  def pending?(_, _), do: false

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
