defmodule Cuckoding.Battles.Stages do
  @moduledoc "Frozen stage order and responsibility; custom stages have read access only."
  alias Cuckoding.Workflows

  @roles %{
    "coordinator" => "summa_rudis",
    "speculator" => "speculator",
    "implementor" => "implementor",
    "secutor" => "secutor",
    "final_secutor" => "secutor",
    "summary" => "summa_rudis"
  }
  @next %{
    "prepare_worktree" => "coordinator",
    "coordinator" => "speculator",
    "speculator" => "implementor",
    "implementor" => "capture",
    "capture" => "checks",
    "combine" => "checks",
    "checks" => "secutor",
    "secutor" => "integrate",
    "final_checks" => "final_secutor",
    "final_secutor" => "summary"
  }

  def policy, do: "read-role-stages-v1"

  def custom(snapshot),
    do:
      if(snapshot["custom_stages"] == policy(),
        do: Workflows.read_stages(snapshot["workflow_definition"]),
        else: []
      )

  def role(snapshot, stage),
    do:
      @roles[stage] || Enum.find_value(custom(snapshot), &if(&1["key"] == stage, do: &1["role"]))

  def next(snapshot, "speculator") do
    case custom(snapshot) do
      [] -> "implementor"
      [first | _] -> first["key"]
    end
  end

  def next(snapshot, "step_" <> _ = stage) do
    case Enum.drop_while(custom(snapshot), &(&1["key"] != stage)) do
      [_, following | _] -> following["key"]
      [_] -> "implementor"
      _ -> raise "unknown frozen workflow stage"
    end
  end

  def next(_, stage), do: Map.fetch!(@next, stage)

  defdelegate custom_key?(key), to: Workflows

  def report_valid?(snapshot, stage, role, provider) do
    if custom_key?(stage),
      do:
        role(snapshot, stage) == role and byte_size(provider["report"]["summary"]) <= 512 and
          Enum.all?(provider["tools"] || [], &(&1["tool"] != "edit_file")),
      else: true
  end

  def merge_context(snapshot, stage, context, result) do
    if Enum.any?(custom(snapshot), &(&1["key"] == stage)) do
      finding = %{"stage" => stage, "summary" => result["provider"]["report"]["summary"]}

      context
      |> Map.merge(Map.delete(result, "summary"))
      |> Map.update("read_stage_summaries", [finding], &(&1 ++ [finding]))
    else
      Map.merge(context, result)
    end
  end
end
