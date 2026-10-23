defmodule Cuckoding.Battles.MixedClosure do
  @moduledoc "Stop-only retained native closure beside an interrupted provider; no advancement."
  alias Cuckoding.Battles.{Attempt, CandidateRecovery, ProviderClosure, Waves}
  alias Cuckoding.Repo

  def policy, do: "retained-mixed-closure-v1"
  def enabled?(snapshot), do: snapshot["mixed_closure"] == policy()

  def pair(battle, attempts) do
    with true <- enabled?(battle.snapshot) and Waves.enabled?(battle.snapshot),
         true <- battle.state in ~w(running pausing) and length(attempts) == 2,
         {[provider], [native]} <- Enum.split_with(attempts, &(not is_nil(&1.role))),
         true <- provider?(battle, provider) and member?(battle, native),
         true <- provider.task_id != native.task_id do
      %{"provider_id" => provider.id, "native_id" => native.id}
    else
      _ -> nil
    end
  end

  def member?(battle, attempt),
    do:
      enabled?(battle.snapshot) and CandidateRecovery.enabled?(battle.snapshot) and
        attempt.state == "interrupted" and CandidateRecovery.member?(battle, attempt)

  def next(battle, completed_id) do
    with %{"provider_id" => ^completed_id, "native_id" => id} = pair <-
           battle.context["mixed_closure_pair"],
         true <- map_size(pair) == 2 and enabled?(battle.snapshot),
         nil <- battle.context["provider_closure_pending"],
         [] <- battle.context["wave_provider_inspections"],
         %Attempt{} = provider <- Repo.get(Attempt, completed_id),
         true <- provider?(battle, provider),
         true <- is_map(battle.context["provider_closures"][completed_id]),
         %Attempt{} = native <- Repo.get(Attempt, id),
         true <- member?(battle, native) and native.task_id != provider.task_id do
      native
    else
      _ -> nil
    end
  end

  def pending?(battle, attempt) do
    enabled?(battle.snapshot) and battle.state == "needs_attention" and
      battle.context["mixed_closure_pending"] == attempt.id and
      battle.current_task_id == attempt.task_id and battle.stage == attempt.stage and
      next(battle, battle.context["mixed_closure_pair"]["provider_id"]) == attempt
  end

  def closed?(battle, attempt) do
    member?(battle, attempt) and battle.context["mixed_closure_pair"]["native_id"] == attempt.id and
      CandidateRecovery.verified?(
        attempt,
        get_in(battle.context, ["mixed_closures", attempt.id, "receipt"])
      )
  end

  defp provider?(battle, attempt),
    do:
      ProviderClosure.enabled?(battle.snapshot) and attempt.battle_id == battle.id and
        attempt.state == "interrupted" and not is_nil(attempt.role) and
        attempt.request["snapshot"] == battle.snapshot
end
