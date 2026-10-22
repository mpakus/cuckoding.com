defmodule Cuckoding.Battles.Slots do
  @moduledoc "Frozen exact role pairs; capacity never selects a substitute binding."
  alias Cuckoding.Battles.Waves
  def policy, do: "assigned-pairs-v1"
  def enabled?(snapshot), do: snapshot["role_slots"] == policy()

  def bindings(snapshot),
    do: snapshot["team"] ++ if(enabled?(snapshot), do: snapshot["parallel_team"] || [], else: [])

  def binding(snapshot, role_id, slot) do
    primary = Enum.find(snapshot["team"], &(&1["id"] == role_id))

    cond do
      not enabled?(snapshot) or slot == 0 -> primary
      slot == 1 -> Enum.find(snapshot["parallel_team"] || [], &(&1["id"] == role_id)) || primary
      true -> nil
    end
  end

  def task_binding(snapshot, role_id, nil), do: binding(snapshot, role_id, 0)

  def task_binding(snapshot, role_id, task) do
    slot = if Waves.enabled?(snapshot), do: task.context["worker_slot"], else: 0
    binding(snapshot, role_id, slot)
  end

  def valid_task?(snapshot, task),
    do:
      not enabled?(snapshot) or not Waves.enabled?(snapshot) or is_nil(task) or
        task.context["worker_slot"] in [0, 1]
end
