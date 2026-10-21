defmodule Cuckoding.Battles.Backoff do
  @moduledoc "Versioned wait metadata; admission and retry authority remain in Battles."
  @policy "automatic-provider-backoff-v1"

  def policy, do: @policy

  def enabled?(battle), do: battle.snapshot["provider_backoff"] == @policy

  def transient?(attempt),
    do: attempt.result["reason"] in ~w(connection_lost profile_busy timeout launch_failed)

  def pending?(nil), do: false

  def pending?(battle) do
    enabled?(battle) and battle.state == "needs_attention" and
      not is_nil(window(battle)) and
      battle.reason == battle.context["provider_backoff"]["reason"]
  end

  def schedule(attempt, used, now) when used in 0..1 do
    delay = Enum.at([5, 20], used)

    %{
      "attempt_id" => attempt.id,
      "reason" => attempt.result["reason"],
      "scheduled_at" => DateTime.to_iso8601(now),
      "due_at" => now |> DateTime.add(delay) |> DateTime.to_iso8601(),
      "delay_seconds" => delay
    }
  end

  def due_at(battle) do
    {_, due} = window(battle)
    {:ok, due, 0}
  end

  def before_wait?(battle, now) do
    {scheduled, _} = window(battle)
    DateTime.compare(now, scheduled) == :lt
  end

  def remaining(battle, now) do
    case window(battle) do
      {_, due} -> max(DateTime.diff(due, now), 0)
      _ -> 0
    end
  end

  defp window(battle) do
    with %{
           "attempt_id" => id,
           "reason" => reason,
           "scheduled_at" => start,
           "due_at" => due,
           "delay_seconds" => delay
         } <- battle.context["provider_backoff"],
         true <-
           is_binary(id) and delay in [5, 20] and
             reason in ~w(connection_lost profile_busy timeout launch_failed),
         true <- is_binary(start) and is_binary(due),
         {:ok, start, 0} <- DateTime.from_iso8601(start),
         {:ok, due, 0} <- DateTime.from_iso8601(due),
         true <- DateTime.compare(DateTime.add(start, delay), due) == :eq do
      {start, due}
    else
      _ -> nil
    end
  end
end
