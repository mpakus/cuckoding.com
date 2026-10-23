defmodule Cuckoding.Battles.Stages do
  @moduledoc "Frozen stage order, responsibility and explicit host file access."
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
  def writer_policy, do: "write-role-stages-v1"

  def writers?(snapshot),
    do:
      snapshot["custom_stages"] == writer_policy() and
        snapshot["workflow_definition"]["version"] == 4

  def custom(snapshot) do
    cond do
      writers?(snapshot) ->
        Workflows.execution_stages(snapshot["workflow_definition"])

      snapshot["custom_stages"] == policy() ->
        Workflows.read_stages(snapshot["workflow_definition"])

      true ->
        []
    end
  end

  def role(snapshot, stage),
    do:
      @roles[stage] || Enum.find_value(custom(snapshot), &if(&1["key"] == stage, do: &1["role"]))

  def access(_, "implementor"), do: "write"

  def access(snapshot, stage) do
    if writers?(snapshot) and
         Enum.any?(custom(snapshot), &(&1["key"] == stage and &1["access"] == "write")),
       do: "write",
       else: "read"
  end

  def pipeline(snapshot) do
    {before, after_steps} = Enum.split_with(custom(snapshot), &(&1["position"] != "after"))

    ["speculator"] ++
      Enum.map(before, & &1["key"]) ++ ["implementor"] ++ Enum.map(after_steps, & &1["key"])
  end

  def next(snapshot, stage, context \\ %{})

  def next(snapshot, "capture", context) do
    if writers?(snapshot),
      do: following(snapshot, Map.fetch!(context, "writer_stage")),
      else: "checks"
  end

  def next(snapshot, stage, _) when stage in ~w(speculator implementor) do
    if access(snapshot, stage) == "write", do: "capture", else: following(snapshot, stage)
  end

  def next(snapshot, "step_" <> _ = stage, _) do
    if access(snapshot, stage) == "write", do: "capture", else: following(snapshot, stage)
  end

  def next(_, stage, _), do: Map.fetch!(@next, stage)

  defp following(snapshot, stage) do
    case Enum.drop_while(pipeline(snapshot), &(&1 != stage)) do
      [_, following | _] -> following
      [_] -> "checks"
      _ -> raise "unknown frozen workflow stage"
    end
  end

  defdelegate custom_key?(key), to: Workflows

  def report_valid?(snapshot, stage, role, provider) do
    if custom_key?(stage),
      do:
        role(snapshot, stage) == role and byte_size(provider["report"]["summary"]) <= 512 and
          (access(snapshot, stage) == "write" or
             Enum.all?(provider["tools"] || [], &(&1["tool"] != "edit_file"))),
      else: true
  end

  def merge_context(snapshot, stage, context, result) do
    merged =
      if Enum.any?(custom(snapshot), &(&1["key"] == stage)) do
        finding = %{"stage" => stage, "summary" => result["provider"]["report"]["summary"]}

        context
        |> Map.merge(Map.delete(result, "summary"))
        |> Map.update("read_stage_summaries", [finding], &(&1 ++ [finding]))
      else
        Map.merge(context, result)
      end

    cond do
      not writers?(snapshot) ->
        merged

      stage == "speculator" ->
        Map.put(merged, "speculator_plan", result["provider"]["report"]["summary"])

      access(snapshot, stage) == "write" ->
        Map.put(merged, "writer_stage", stage)

      true ->
        merged
    end
  end
end
