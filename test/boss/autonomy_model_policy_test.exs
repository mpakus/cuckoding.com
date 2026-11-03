defmodule Boss.AutonomyModelPolicyTest do
  use ExUnit.Case, async: true
  alias Boss.Agents.Codex
  alias Boss.Deliveries.ModelPolicy

  test "saved legacy policy retains its execution budget and CLI defaults" do
    for version <- [nil, 0] do
      assert ModelPolicy.max_cycles(version) == 3
      assert ModelPolicy.max_steps(version) == 20
      assert ModelPolicy.route(version, :implement, 1) == nil
      assert Codex.args(:implement, nil, nil) == Codex.args()
      assert Codex.args(:plan, "/tmp/report", nil) == Codex.args(:plan, "/tmp/report")
    end
  end

  test "new policy uses cheap routing only for an explicit small plan and escalates repairs" do
    version = ModelPolicy.current()
    assert version == 1
    assert ModelPolicy.max_cycles(version) == 5
    assert ModelPolicy.max_steps(version) == 48
    assert ModelPolicy.max_steps(version) >= 7 + 2 + 5 * 4 + 4 * 2 + 5

    for plan <- [nil, %{}, %{"complexity" => "standard"}, %{"complexity" => "complex"}] do
      assert ModelPolicy.route(version, :implement, 1, plan) ==
               %{"model" => "gpt-6.1-sol", "reasoning_effort" => "high"}
    end

    small = %{"complexity" => "small"}

    assert ModelPolicy.route(version, :implement, 1, small) ==
             %{"model" => "gpt-6-luna", "reasoning_effort" => "medium"}

    assert Enum.map(2..5, &ModelPolicy.route(version, :implement, &1, small)) == [
             %{"model" => "gpt-6-astra", "reasoning_effort" => "xhigh"},
             %{"model" => "gpt-6.1-sol", "reasoning_effort" => "xhigh"},
             %{"model" => "gpt-6-astra", "reasoning_effort" => "xhigh"},
             %{"model" => "gpt-6.1-sol", "reasoning_effort" => "xhigh"}
           ]

    assert ModelPolicy.route(version, :resolve, 1)["model"] == "gpt-6-astra"
    assert ModelPolicy.route(version, :resolve, 2)["model"] == "gpt-6.1-sol"
    assert ModelPolicy.route(version, :resolve, 2)["reasoning_effort"] == "xhigh"

    for kind <- [:plan, :review, :merge_review, :intake] do
      assert ModelPolicy.route(version, kind, 0)["model"] == "gpt-6.1-sol"
    end

    assert_raise FunctionClauseError, fn -> ModelPolicy.route(1, :resolve, 3) end
    assert_raise FunctionClauseError, fn -> ModelPolicy.route(1, :implement, 6) end
    assert_raise FunctionClauseError, fn -> ModelPolicy.max_steps(2) end
  end

  test "pinned model arguments keep stdin, sandbox and report contracts" do
    profile = ModelPolicy.route(1, :resolve, 1)

    for kind <- [:plan, :review, :resolve] do
      args = Codex.args(kind, "/tmp/owned-report.json", profile)
      assert flag(args, "--model") == "gpt-6-astra"
      assert flag(args, "--config") == ~s(model_reasoning_effort="xhigh")
      assert flag(args, "--sandbox") == "read-only"
      assert flag(args, "--output-last-message") == "/tmp/owned-report.json"
      assert List.last(args) == "-"
      assert "--ephemeral" in args and "--ignore-user-config" in args
      refute Enum.any?(args, &String.contains?(&1, "bypass"))
    end

    args = Codex.args(:implement, nil, ModelPolicy.route(1, :implement, 1))
    assert flag(args, "--sandbox") == "workspace-write"
    assert flag(args, "--model") == "gpt-6.1-sol"
    refute "--output-schema" in args
    assert List.last(args) == "-"

    args = Codex.args(:resolve, "/tmp/report.json", profile)

    assert flag(args, "--output-schema") ==
             Application.app_dir(:boss, "priv/resolution_schema.json")

    assert_raise FunctionClauseError, fn ->
      Codex.args(:plan, "/tmp/report", %{
        "model" => "other-provider",
        "reasoning_effort" => "high"
      })
    end
  end

  defp flag(args, name), do: Enum.at(args, Enum.find_index(args, &(&1 == name)) + 1)
end
