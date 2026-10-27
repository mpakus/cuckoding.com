defmodule Boss.DeliveryProtocolTest do
  use ExUnit.Case, async: true
  alias Boss.Deliveries.Protocol
  alias Boss.Agents.Codex

  @plan %{
    "summary" => "Add greeting",
    "steps" => ["Implement greeting"],
    "acceptance" => ["Says hello"]
  }

  test "one exact bounded typed plan preserves criteria" do
    assert {:ok, @plan} = Protocol.plan(JSON.encode!(@plan))

    for invalid <- [
          JSON.encode!(@plan) <> "{}",
          String.replace(JSON.encode!(@plan), "{", ~s({"summary":"overwrite",), global: false),
          JSON.encode!(Map.put(@plan, "extra", true)),
          JSON.encode!(%{@plan | "acceptance" => ["Says hello", "Says hello"]}),
          JSON.encode!(%{@plan | "steps" => []}),
          JSON.encode!(%{@plan | "summary" => " "}),
          JSON.encode!(%{@plan | "acceptance" => [String.duplicate("x", 1001)]}),
          String.duplicate("x", 32_769),
          <<255>>
        ] do
      assert {:error, :invalid_plan} = Protocol.plan(invalid)
    end
  end

  test "review must cover the saved plan criteria exactly" do
    report = %{
      "verdict" => "approved",
      "summary" => "Matches",
      "acceptance" => [
        %{"criterion" => "Says hello", "status" => "passed", "evidence" => "greeting.ex:1"}
      ],
      "issues" => []
    }

    assert {:ok, ^report} = Protocol.review(JSON.encode!(report), @plan)

    assert {:error, :invalid_review} =
             Protocol.review(JSON.encode!(report), %{@plan | "acceptance" => ["Says goodbye"]})

    assert {:error, :invalid_review} =
             Protocol.review(JSON.encode!(report), %{
               @plan
               | "acceptance" => ["Says hello", "Handles errors"]
             })
  end

  test "plan is fresh read-only; prompts include full explicit inputs without truncation" do
    args = Codex.args(:plan, "/tmp/report.json")
    assert Enum.at(args, Enum.find_index(args, &(&1 == "--sandbox")) + 1) == "read-only"
    assert "--ephemeral" in args and "--ignore-user-config" in args
    assert Application.app_dir(:boss, "priv/plan_schema.json") in args
    refute "resume" in args

    for kind <- [:plan, :implement, :review] do
      assert {:ok, prompt} = Protocol.prompt(kind, %{"specification" => "hello", "plan" => @plan})
      assert prompt =~ "hello" and prompt =~ "Says hello"

      assert {:error, :input_too_large} =
               Protocol.prompt(kind, %{"source" => String.duplicate("x", 1_048_576)})
    end
  end
end
