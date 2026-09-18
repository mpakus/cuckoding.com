defmodule Cuckoding.Workflows.DefinitionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Cuckoding.Workflows.Definition

  test "the default template evaluates gates and labeled transitions" do
    workflow = Definition.default()

    assert {:ok, %{"stage_key" => "development"}} =
             Definition.evaluate(workflow, "specification", "pass")

    assert {:ok, %{"stage_key" => "development"}} =
             Definition.evaluate(workflow, "qa", "fix_code")

    assert {:ok, %{"status" => "done"}} =
             Definition.evaluate(workflow, "release_handoff", "pass")
  end

  test "a custom template enforces gates and finite budgets" do
    workflow = %{
      "entry" => "build",
      "stages" => [
        %{
          "key" => "build",
          "name" => "Build",
          "role" => "implementer",
          "role_kind" => "agent",
          "budgets" => %{
            "max_attempts" => 2,
            "active_ms" => 100,
            "wall_ms" => 200,
            "tokens" => 300,
            "cost_micros" => 400
          },
          "knowledge_triggers" => ["task_started"],
          "checkpoint_interval_ms" => 50,
          "gates" => ["tests"],
          "transitions" => %{"pass" => "$done"}
        }
      ]
    }

    assert {:error, {:gates_failed, ["tests"]}} =
             Definition.evaluate(workflow, "build", "pass")

    assert {:error, {:budget_exceeded, "max_attempts"}} =
             Definition.evaluate(workflow, "build", "pass", %{
               "attempt" => 3,
               "passed_gates" => ["tests"]
             })

    assert {:ok, %{"status" => "done"}} =
             Definition.evaluate(workflow, "build", "pass", %{
               "attempt" => 2,
               "passed_gates" => ["tests"]
             })
  end

  test "findings route by transition label" do
    findings = [
      %{"summary" => "Implementation bug", "transition" => "fix_code"},
      %{"summary" => "Ambiguous intent", "transition" => "fix_intent"},
      %{"summary" => "Second bug", "transition" => "fix_code"}
    ]

    assert {:ok, routed} = Definition.route_findings(Definition.default(), "qa", findings)

    assert Enum.map(routed["development"], & &1["summary"]) == [
             "Implementation bug",
             "Second bug"
           ]

    assert Enum.map(routed["specification"], & &1["summary"]) == ["Ambiguous intent"]
  end

  test "invalid structure fails closed" do
    assert {:error, {:invalid_workflow, :missing_stages}} = Definition.validate(%{})

    assert {:error, {:invalid_workflow, {:unknown_role_kind, "robot"}}} =
             Definition.validate(%{
               "stages" => [
                 %{"key" => "build", "role" => "builder", "role_kind" => "robot"}
               ]
             })

    assert {:error, {:invalid_workflow, {:unknown_transition_target, "missing"}}} =
             Definition.validate(%{
               "stages" => [
                 %{
                   "key" => "build",
                   "role" => "builder",
                   "transitions" => %{"pass" => "missing"}
                 }
               ]
             })

    assert {:error, {:invalid_workflow, :invalid_budgets}} =
             Definition.validate(%{
               "stages" => [%{"key" => "build", "role" => "builder", "budgets" => []}]
             })
  end

  property "every generated pass-only cycle is rejected" do
    check all(stage_count <- integer(1..12), max_runs: 30) do
      keys = Enum.map(1..stage_count, &"stage_#{&1}")

      stages =
        keys
        |> Enum.with_index()
        |> Enum.map(fn {key, index} ->
          %{
            "key" => key,
            "role" => "worker",
            "transitions" => %{"pass" => Enum.at(keys, rem(index + 1, stage_count))}
          }
        end)

      assert {:error, {:invalid_workflow, {:unsafe_cycle, _keys}}} =
               Definition.validate(%{"entry" => hd(keys), "stages" => stages})
    end
  end

  property "generated acyclic templates always reach done" do
    check all(stage_count <- integer(1..12), max_runs: 30) do
      keys = Enum.map(1..stage_count, &"stage_#{&1}")

      workflow = %{
        "entry" => hd(keys),
        "stages" =>
          keys
          |> Enum.with_index()
          |> Enum.map(fn {key, index} ->
            %{
              "key" => key,
              "role" => "worker",
              "transitions" => %{"pass" => Enum.at(keys, index + 1, "$done")}
            }
          end)
      }

      final =
        Enum.reduce(keys, nil, fn key, _previous ->
          assert {:ok, result} = Definition.evaluate(workflow, key, "pass")
          result
        end)

      assert final["status"] == "done"
    end
  end
end
