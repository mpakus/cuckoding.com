defmodule Cuckoding.Battles.CandidateRecovery do
  @moduledoc "Exact retained capture/preparation checkpoint evidence, without replay."
  alias Cuckoding.Battles.{Attempt, PreparationRecovery, Receipts}
  alias Cuckoding.LocalGit
  @envelope ~w(battle_id request_id task_id stage criteria_sha256)

  def policy, do: "retained-candidate-wave-v1"
  def enabled?(snapshot), do: snapshot["candidate_recovery"] == policy()
  def combination_policy, do: "retained-combination-v1"

  def combination_enabled?(snapshot),
    do: snapshot["combination_recovery"] == combination_policy()

  def eligible?(battle, [%Attempt{stage: "combine"} = attempt]),
    do:
      enabled?(battle.snapshot) and battle.state in ~w(running pausing) and
        member?(battle, attempt)

  def eligible?(battle, attempts) do
    enabled?(battle.snapshot) and battle.state in ~w(running pausing) and
      length(attempts) in 1..2 and Enum.any?(attempts, &(&1.stage == "capture")) and
      (length(attempts) == 1 or battle.snapshot["parallelism"] == "parallel-waves-v1") and
      length(Enum.uniq_by(attempts, & &1.task_id)) == length(attempts) and
      Enum.all?(attempts, &(&1.stage in ~w(capture prepare_worktree))) and
      Enum.all?(attempts, &member?(battle, &1))
  end

  def member?(battle, %Attempt{role: nil, stage: stage} = attempt)
      when stage in ~w(capture prepare_worktree),
      do:
        not is_nil(attempt.task_id) and attempt.battle_id == battle.id and
          attempt.request["snapshot"] == battle.snapshot

  def member?(battle, %Attempt{role: nil, stage: "combine"} = attempt),
    do:
      combination_enabled?(battle.snapshot) and
        battle.snapshot["parallelism"] == "parallel-waves-v1" and
        not is_nil(attempt.task_id) and attempt.battle_id == battle.id and
        attempt.request["snapshot"] == battle.snapshot

  def member?(_, _), do: false

  def pending?(battle, attempt) do
    enabled?(battle.snapshot) and battle.state == "needs_attention" and member?(battle, attempt) and
      battle.context["candidate_recovery_pending"] == attempt.id and
      battle.current_task_id == attempt.task_id and battle.stage == attempt.stage and
      queue_current?(battle.context["candidate_recovery_wave"], attempt.id)
  end

  defp queue_current?(%{"attempt_ids" => ids, "remaining_ids" => remaining}, id)
       when is_list(ids) and is_list(remaining) and length(ids) in 1..2 and
              length(remaining) in 1..2 do
    length(Enum.uniq(ids)) == length(ids) and hd(remaining) == id and
      remaining == Enum.drop(ids, length(ids) - length(remaining))
  end

  defp queue_current?(_, _), do: false

  def verified?(%Attempt{stage: "prepare_worktree"} = attempt, result),
    do: enabled?(attempt.request["snapshot"]) and PreparationRecovery.verified?(attempt, result)

  def verified?(
        %Attempt{stage: "combine"} = attempt,
        %{"status" => "combined", "cleanup_verified" => true} = result
      ) do
    context = attempt.request["context"]
    original = attempt.request["task_context"]["native_candidate"]

    enabled?(attempt.request["snapshot"]) and combination_enabled?(attempt.request["snapshot"]) and
      Receipts.bound?(attempt, result) and Receipts.payload_valid?(attempt, result) and
      Map.keys(result) --
        (@envelope ++ ~w(status cleanup_verified candidate_sha native_candidate)) == [] and
      is_map(original) and original["status"] == "candidate_captured" and
      LocalGit.normalize(original) == original and
      context["head"] == context["native_battle"]["head"]
  end

  def verified?(
        %Attempt{stage: "capture"} = attempt,
        %{"status" => "captured", "cleanup_verified" => true} = result
      ) do
    preparation = attempt.request["task_context"]["preparation"]
    candidate = result["native_candidate"]

    expected = %{
      "status" => "candidate_captured",
      "key" => attempt.id,
      "worktree_key" => preparation["key"],
      "base" => preparation["head"]
    }

    enabled?(attempt.request["snapshot"]) and Receipts.bound?(attempt, result) and
      Map.keys(result) --
        (@envelope ++ ~w(status cleanup_verified candidate_sha native_candidate)) == [] and
      is_map(candidate) and LocalGit.normalize(candidate) == candidate and
      Map.take(candidate, Map.keys(expected)) == expected and
      preparation["head"] == attempt.request["context"]["head"] and
      result["candidate_sha"] == candidate["candidate"]
  end

  def verified?(_, _), do: false

  defdelegate failed?(attempt, result), to: PreparationRecovery

  def reconciled?(battle, attempt),
    do:
      enabled?(battle.snapshot) and attempt.state == "interrupted" and
        verified?(
          attempt,
          get_in(battle.context, ["candidate_reconciliations", attempt.id, "receipt"])
        )
end
