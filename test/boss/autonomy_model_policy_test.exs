defmodule Boss.AutonomyModelPolicyTest do
  use ExUnit.Case, async: true
  alias Boss.Agents.Codex
  alias Boss.Deliveries.ModelPolicy

  test "timeout recovery requires its new policy and an actual known-clean timeout receipt" do
    step = %{
      kind: "implement",
      status: "failed",
      receipt: %{
        "outcome" => "timeout",
        "cleanup" => "group_empty",
        "exit_kind" => "signal",
        "exit_code" => nil,
        "signal" => 15,
        "eof" => %{"stdout" => true, "stderr" => true}
      }
    }

    assert ModelPolicy.current_execution_recovery() == 1
    assert ModelPolicy.timeout_recoverable?(1, step)
    refute ModelPolicy.timeout_recoverable?(0, step)
    refute ModelPolicy.timeout_recoverable?(nil, step)
    refute ModelPolicy.timeout_recoverable?(1, %{step | kind: "plan"})
    refute ModelPolicy.timeout_recoverable?(1, %{step | status: "cancelled"})

    for invalid <- [nil, [], "timeout"],
        do: refute(ModelPolicy.timeout_recoverable?(1, %{step | receipt: invalid}))

    for changes <- [
          %{"outcome" => "cancelled"},
          %{"outcome" => "exited"},
          %{"cleanup" => "unknown"},
          %{"eof" => %{"stdout" => true, "stderr" => false}},
          %{"exit_kind" => nil},
          %{"signal" => nil},
          %{"signal" => 129},
          %{"exit_code" => 0},
          %{"exit_kind" => "exit", "exit_code" => 0}
        ] do
      refute ModelPolicy.timeout_recoverable?(1, %{
               step
               | receipt: Map.merge(step.receipt, changes)
             })
    end

    exited = Map.merge(step.receipt, %{"exit_kind" => "exit", "exit_code" => 0, "signal" => nil})
    assert ModelPolicy.timeout_recoverable?(1, %{step | receipt: exited})
  end

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

  test "delivery exclusions preserve the preferred route and use only strong fallbacks" do
    sol = ModelPolicy.route(1, :implement, 1)
    astra = ModelPolicy.route(1, :resolve, 1)
    luna = ModelPolicy.route(1, :implement, 1, %{"complexity" => "small"})

    assert {:ok, ^sol} = ModelPolicy.select(sol, [])
    assert {:ok, ^sol} = ModelPolicy.select(sol, ["gpt-6-astra"])
    assert {:ok, ^astra} = ModelPolicy.select(sol, ["gpt-6.1-sol"])

    assert {:ok, %{"model" => "gpt-6.1-sol", "reasoning_effort" => "xhigh"}} =
             ModelPolicy.select(astra, ["gpt-6-astra"])

    assert {:ok, ^luna} = ModelPolicy.select(luna, ["gpt-6.1-sol", "gpt-6-astra"])

    assert {:ok, %{"model" => "gpt-6.1-sol", "reasoning_effort" => "xhigh"}} =
             ModelPolicy.select(luna, ["gpt-6-luna"])

    assert {:ok, ^astra} = ModelPolicy.select(luna, ["gpt-6-luna", "gpt-6.1-sol"])

    for preferred <- [sol, astra] do
      assert {:error, :models_exhausted} =
               ModelPolicy.select(preferred, ["gpt-6.1-sol", "gpt-6-astra"])
    end

    assert {:error, :models_exhausted} =
             ModelPolicy.select(luna, ["gpt-6-luna", "gpt-6.1-sol", "gpt-6-astra"])

    assert {:ok, nil} = ModelPolicy.select(nil, ["gpt-6.1-sol", "gpt-6-astra"])
  end

  defp flag(args, name), do: Enum.at(args, Enum.find_index(args, &(&1 == name)) + 1)
end
