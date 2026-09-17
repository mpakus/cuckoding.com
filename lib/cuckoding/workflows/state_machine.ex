defmodule Cuckoding.Workflows.StateMachine do
  @moduledoc """
  Declares the durable task and run transition graphs from `docs/FLOW.md`.
  """

  @task_transitions %{
    "draft" => ~w(ready cancelled archived),
    "ready" => ~w(draft running cancelled archived),
    "running" => ~w(waiting paused hibernated blocked done failed cancelled),
    "waiting" => ~w(running paused hibernated blocked failed cancelled),
    "paused" => ~w(running hibernated cancelled),
    "hibernated" => ~w(running cancelled archived),
    "blocked" => ~w(running waiting failed cancelled),
    "done" => ~w(archived),
    "failed" => ~w(ready archived),
    "cancelled" => ~w(ready archived),
    "archived" => ~w(draft)
  }

  @run_transitions %{
    "queued" => ~w(running cancelled),
    "running" => ~w(waiting paused hibernated blocked done failed cancelled),
    "waiting" => ~w(running paused hibernated blocked failed cancelled),
    "paused" => ~w(running hibernated cancelled),
    "hibernated" => ~w(running cancelled),
    "blocked" => ~w(running waiting failed cancelled),
    "done" => [],
    "failed" => [],
    "cancelled" => []
  }

  def states(:task), do: Map.keys(@task_transitions)
  def states(:run), do: Map.keys(@run_transitions)

  def transitions(kind) do
    for {from, destinations} <- transition_map(kind), to <- destinations, do: {from, to}
  end

  def validate(kind, from, to, wait_reason \\ nil) do
    transitions = transition_map(kind)

    cond do
      not Map.has_key?(transitions, from) -> {:error, :unknown_current_state}
      to not in Map.keys(transitions) -> {:error, :unknown_target_state}
      to not in Map.fetch!(transitions, from) -> {:error, :invalid_transition}
      to == "waiting" and blank?(wait_reason) -> {:error, :wait_reason_required}
      true -> :ok
    end
  end

  defp transition_map(:task), do: @task_transitions
  defp transition_map(:run), do: @run_transitions

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
