defmodule Boss.Tasks.Transition do
  @moduledoc "Pure transition policy. Execution gates stay closed until their producers exist."

  @recovery_gates %{
    "new" => nil,
    "planning" => :runner,
    "ready" => :runner,
    "implementing" => :runner,
    "testing" => :checks,
    "reviewing" => :review,
    "approved" => :review,
    "ready_to_merge" => :integration,
    "integrating" => :integration
  }
  @workflow Map.keys(@recovery_gates)
  @active ~w(planning implementing testing reviewing integrating)
  @exceptional ~w(blocked needs_input failed interrupted cancelled)
  @states @workflow ++ @exceptional ++ ["done"]
  @attention %{
    "block" => "blocked",
    "needs_input" => "needs_input",
    "cancel" => "cancelled",
    "fail" => "failed",
    "interrupt" => "interrupted"
  }
  @forward %{
    {"new", "start_planning"} => :runner,
    {"planning", "finish_planning"} => :runner,
    {"ready", "start_implementation"} => :runner,
    {"implementing", "finish_implementation"} => :runner,
    {"testing", "checks_passed"} => :checks,
    {"reviewing", "approve_review"} => :review,
    {"reviewing", "request_changes"} => :review,
    {"reviewing", "revise_spec"} => :review,
    {"approved", "queue_merge"} => :integration,
    {"approved", "start_integration"} => :integration,
    {"ready_to_merge", "start_integration"} => :integration,
    {"integrating", "finish_integration"} => :integration
  }
  @actions Enum.map(Map.keys(@forward), &elem(&1, 1)) ++ Map.keys(@attention) ++ ~w(resume retry)

  def apply(%{state: state, recovery_state: _, attention_reason: _} = task, action, reason)
      when state in @states do
    cond do
      action not in @actions -> {:error, :invalid_action}
      state == "done" -> {:error, :invalid_transition}
      not valid_reason?(action, reason) -> {:error, :invalid_reason}
      action in ~w(resume retry) -> recover(task, action)
      is_map_key(@attention, action) -> attention(task, action, reason)
      producer = @forward[{state, action}] -> {:error, {:gate_unavailable, producer}}
      true -> {:error, :invalid_transition}
    end
  end

  def apply(_, _, _), do: {:error, :invalid_task}

  def dependency_satisfied?(%{state: "done"}), do: true
  def dependency_satisfied?(_), do: false

  defp attention(task, action, reason) do
    destination = @attention[action]

    cond do
      task.state == "cancelled" or task.state == destination ->
        {:error, :invalid_transition}

      action in ~w(fail interrupt) and task.state not in @active ->
        {:error, :invalid_transition}

      true ->
        recovery = if task.state in @exceptional, do: task.recovery_state, else: task.state

        if recovery in @workflow,
          do: {:ok, attrs(destination, recovery, reason)},
          else: {:error, :invalid_recovery_state}
    end
  end

  defp recover(task, action) do
    allowed =
      (action == "resume" and task.state in ~w(blocked needs_input)) or
        (action == "retry" and task.state in ~w(failed interrupted cancelled))

    if allowed do
      case Map.fetch(@recovery_gates, task.recovery_state) do
        {:ok, nil} -> {:ok, attrs("new", nil, nil)}
        {:ok, producer} -> {:error, {:gate_unavailable, producer}}
        :error -> {:error, :invalid_recovery_state}
      end
    else
      {:error, :invalid_transition}
    end
  end

  defp valid_reason?(action, reason) when is_map_key(@attention, action) do
    is_binary(reason) and byte_size(reason) in 1..1000 and String.valid?(reason) and
      String.trim(reason) != "" and not String.contains?(reason, <<0>>)
  end

  defp valid_reason?(_, reason), do: is_nil(reason)

  defp attrs(state, recovery, reason),
    do: %{state: state, recovery_state: recovery, attention_reason: reason}
end
