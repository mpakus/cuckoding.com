defmodule Cuckoding.Workflows.Definition do
  @moduledoc "Validates and evaluates immutable workflow definitions."

  @role_kinds ~w(agent human system)
  @terminal "$done"
  @default_budgets %{
    "max_attempts" => 3,
    "active_ms" => 1_800_000,
    "wall_ms" => 3_600_000,
    "tokens" => 200_000,
    "cost_micros" => 100_000_000
  }

  @doc "Returns the product's default feature workflow template."
  def default do
    %{
      "entry" => "specification",
      "stages" => [
        %{
          "key" => "specification",
          "role" => "spec_writer",
          "transitions" => %{"pass" => "development", "revise" => "specification"}
        },
        %{
          "key" => "development",
          "role" => "implementer",
          "transitions" => %{"pass" => "qa"}
        },
        %{
          "key" => "qa",
          "role" => "reviewer",
          "transitions" => %{
            "pass" => "human_approval",
            "fix_code" => "specification",
            "fix_intent" => "specification"
          }
        },
        %{
          "key" => "human_approval",
          "role" => "approver",
          "transitions" => %{"approve" => "release_handoff", "changes" => "development"}
        },
        %{"key" => "release_handoff", "role" => "release"}
      ]
    }
  end

  @doc "Validates a workflow and returns its explicit normalized form."
  def validate(%{"stages" => stages} = definition) when is_list(stages) and stages != [] do
    with {:ok, keys} <- stage_keys(stages),
         :ok <- unique(keys),
         {:ok, normalized} <- normalize_stages(stages, keys),
         entry = Map.get(definition, "entry", hd(keys)),
         :ok <- member(entry, keys, :unknown_entry_stage),
         :ok <- transition_targets(normalized, keys),
         :ok <- graph_valid(normalized, entry) do
      {:ok, Map.merge(definition, %{"entry" => entry, "stages" => normalized})}
    end
  end

  def validate(%{"stages" => []}), do: {:error, {:invalid_workflow, :missing_stages}}
  def validate(_definition), do: {:error, {:invalid_workflow, :missing_stages}}

  @doc "Evaluates one labeled transition after checking gates and finite budgets."
  def evaluate(definition, stage_key, label, context \\ %{})

  def evaluate(definition, stage_key, label, context)
      when is_binary(stage_key) and is_binary(label) and is_map(context) do
    with {:ok, workflow} <- validate(definition),
         {:ok, stage} <- fetch_stage(workflow, stage_key),
         :ok <- within_budgets(stage["budgets"], context),
         :ok <- gates_passed(stage["gates"], context),
         {:ok, target} <- fetch_transition(stage, label) do
      result = %{"from" => stage_key, "label" => label, "target" => target}

      if target == @terminal,
        do: {:ok, Map.put(result, "status", "done")},
        else: {:ok, Map.merge(result, %{"status" => "ready", "stage_key" => target})}
    end
  end

  def evaluate(_definition, _stage_key, _label, _context),
    do: {:error, {:invalid_workflow, :invalid_evaluation}}

  @doc "Groups findings by the target selected by each finding's transition label."
  def route_findings(definition, stage_key, findings)
      when is_binary(stage_key) and is_list(findings) do
    with {:ok, workflow} <- validate(definition),
         {:ok, stage} <- fetch_stage(workflow, stage_key) do
      Enum.reduce_while(findings, {:ok, %{}}, &route_finding(stage, &1, &2))
    end
  end

  def route_findings(_definition, _stage_key, _findings),
    do: {:error, {:invalid_workflow, :invalid_findings}}

  defp route_finding(stage, finding, {:ok, routed}) do
    label = is_map(finding) && (finding["transition"] || finding[:transition])

    case fetch_transition(stage, label) do
      {:ok, target} ->
        {:cont, {:ok, Map.update(routed, target, [finding], &(&1 ++ [finding]))}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp stage_keys(stages) do
    Enum.reduce_while(stages, {:ok, []}, fn
      %{"key" => key}, {:ok, keys} when is_binary(key) and key != "" ->
        {:cont, {:ok, keys ++ [key]}}

      _stage, _acc ->
        {:halt, {:error, {:invalid_workflow, :invalid_stage_key}}}
    end)
  end

  defp unique(keys) do
    if Enum.uniq(keys) == keys,
      do: :ok,
      else: {:error, {:invalid_workflow, :duplicate_stage_key}}
  end

  defp normalize_stages(stages, keys) do
    stages
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {stage, index}, {:ok, normalized} ->
      next = Enum.at(keys, index + 1, @terminal)

      case normalize_stage(stage, next) do
        {:ok, value} -> {:cont, {:ok, normalized ++ [value]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_stage(%{"key" => key, "role" => role} = stage, next)
       when is_binary(role) and role != "" do
    role_kind = Map.get(stage, "role_kind", infer_role_kind(role))
    budgets = merge_budgets(Map.get(stage, "budgets", %{}))
    transitions = Map.get(stage, "transitions", %{"pass" => next})
    triggers = Map.get(stage, "knowledge_triggers", [])
    gates = Map.get(stage, "gates", [])
    checkpoint = Map.get(stage, "checkpoint_interval_ms", 60_000)

    with :ok <- member(role_kind, @role_kinds, :unknown_role_kind),
         :ok <- positive_budget(budgets),
         :ok <- string_map(transitions, :invalid_transitions),
         :ok <- string_list(triggers, :invalid_knowledge_triggers),
         :ok <- string_list(gates, :invalid_gates),
         true <- is_integer(checkpoint) and checkpoint > 0 do
      {:ok,
       Map.merge(stage, %{
         "name" => Map.get(stage, "name", humanize(key)),
         "role_kind" => role_kind,
         "budgets" => budgets,
         "transitions" => transitions,
         "knowledge_triggers" => triggers,
         "gates" => gates,
         "checkpoint_interval_ms" => checkpoint
       })}
    else
      false -> {:error, {:invalid_workflow, :invalid_checkpoint_interval}}
      error -> error
    end
  end

  defp normalize_stage(_stage, _next),
    do: {:error, {:invalid_workflow, :invalid_stage}}

  defp infer_role_kind("approver"), do: "human"
  defp infer_role_kind("release"), do: "system"
  defp infer_role_kind(_role), do: "agent"

  defp merge_budgets(budgets) when is_map(budgets), do: Map.merge(@default_budgets, budgets)
  defp merge_budgets(budgets), do: budgets

  defp positive_budget(budgets) when is_map(budgets) do
    if Enum.all?(@default_budgets, &valid_budget?(budgets, &1)),
      do: :ok,
      else: {:error, {:invalid_workflow, :invalid_budgets}}
  end

  defp positive_budget(_budgets), do: {:error, {:invalid_workflow, :invalid_budgets}}

  defp valid_budget?(budgets, {key, _default}) do
    value = budgets[key]
    is_integer(value) and value > 0
  end

  defp string_map(values, reason) when is_map(values) and map_size(values) > 0 do
    if Enum.all?(values, fn {key, value} ->
         is_binary(key) and key != "" and is_binary(value) and value != ""
       end),
       do: :ok,
       else: {:error, {:invalid_workflow, reason}}
  end

  defp string_map(_values, reason), do: {:error, {:invalid_workflow, reason}}

  defp string_list(values, reason) when is_list(values) do
    if Enum.all?(values, &(is_binary(&1) and &1 != "")),
      do: :ok,
      else: {:error, {:invalid_workflow, reason}}
  end

  defp string_list(_values, reason), do: {:error, {:invalid_workflow, reason}}

  defp transition_targets(stages, keys) do
    invalid = Enum.find_value(stages, &invalid_target(&1, keys))

    if invalid,
      do: {:error, {:invalid_workflow, {:unknown_transition_target, invalid}}},
      else: :ok
  end

  defp invalid_target(stage, keys) do
    Enum.find_value(stage["transitions"], fn {_label, target} ->
      if target == @terminal or target in keys, do: nil, else: target
    end)
  end

  defp graph_valid(stages, entry) do
    graph = :digraph.new()

    try do
      Enum.each(stages, &:digraph.add_vertex(graph, &1["key"]))

      Enum.each(stages, fn stage ->
        Enum.each(stage["transitions"], fn {label, target} ->
          if target != @terminal, do: :digraph.add_edge(graph, stage["key"], target, label)
        end)
      end)

      keys = Enum.map(stages, & &1["key"])
      unreachable = keys -- :digraph_utils.reachable([entry], graph)

      cond do
        unreachable != [] ->
          {:error, {:invalid_workflow, {:unreachable_stages, Enum.sort(unreachable)}}}

        unsafe = unsafe_cycle(stages, graph) ->
          {:error, {:invalid_workflow, {:unsafe_cycle, unsafe}}}

        true ->
          :ok
      end
    after
      :digraph.delete(graph)
    end
  end

  defp unsafe_cycle(stages, graph) do
    stages_by_key = Map.new(stages, &{&1["key"], &1})

    Enum.find_value(:digraph_utils.strong_components(graph), fn component ->
      labels = internal_labels(component, stages_by_key)
      cycle? = length(component) > 1 or labels != []

      if cycle? and Enum.all?(labels, &(&1 == "pass")), do: Enum.sort(component)
    end)
  end

  defp internal_labels(component, stages_by_key) do
    Enum.flat_map(component, &internal_stage_labels(&1, component, stages_by_key))
  end

  defp internal_stage_labels(key, component, stages_by_key) do
    stages_by_key
    |> Map.fetch!(key)
    |> Map.fetch!("transitions")
    |> Enum.flat_map(fn {label, target} -> if target in component, do: [label], else: [] end)
  end

  defp fetch_stage(workflow, stage_key) do
    case Enum.find(workflow["stages"], &(&1["key"] == stage_key)) do
      nil -> {:error, {:invalid_workflow, {:unknown_stage, stage_key}}}
      stage -> {:ok, stage}
    end
  end

  defp fetch_transition(_stage, label) when not is_binary(label) or label == "",
    do: {:error, {:invalid_workflow, :invalid_transition_label}}

  defp fetch_transition(stage, label) do
    case Map.fetch(stage["transitions"], label) do
      {:ok, target} -> {:ok, target}
      :error -> {:error, {:invalid_workflow, {:unknown_transition_label, label}}}
    end
  end

  defp within_budgets(budgets, context) do
    checks = [
      {"attempt", "max_attempts", 1},
      {"active_ms", "active_ms", 0},
      {"wall_ms", "wall_ms", 0},
      {"tokens", "tokens", 0},
      {"cost_micros", "cost_micros", 0}
    ]

    case Enum.find(checks, fn {usage_key, limit_key, default} ->
           value = Map.get(context, usage_key, default)
           not is_integer(value) or value < 0 or value > budgets[limit_key]
         end) do
      nil -> :ok
      {_usage_key, limit_key, _default} -> {:error, {:budget_exceeded, limit_key}}
    end
  end

  defp gates_passed(gates, context) do
    passed = Map.get(context, "passed_gates", [])

    if is_list(passed) do
      case gates -- passed do
        [] -> :ok
        missing -> {:error, {:gates_failed, missing}}
      end
    else
      {:error, {:invalid_workflow, :invalid_gate_context}}
    end
  end

  defp member(value, values, reason) do
    if value in values, do: :ok, else: {:error, {:invalid_workflow, {reason, value}}}
  end

  defp humanize(key), do: key |> String.replace("_", " ") |> String.capitalize()
end
