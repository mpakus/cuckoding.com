defmodule Boss.DeliveryProtocolTest do
  use ExUnit.Case, async: true
  alias Boss.Deliveries.Protocol
  alias Boss.Deliveries.FileScopes
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

  test "typed file predictions preserve paths; legacy and null scopes are unknown" do
    scopes = [
      %{"path" => "lib/Hello.ex", "kind" => "file"},
      %{"path" => "test", "kind" => "directory"}
    ]

    plan = Map.put(@plan, "file_scopes", scopes)
    assert {:ok, ^plan} = Protocol.plan(JSON.encode!(plan))
    unknown = Map.put(@plan, "file_scopes", nil)
    assert {:ok, ^unknown} = Protocol.plan(JSON.encode!(unknown))

    for invalid <- [
          [],
          %{},
          true,
          ["lib"],
          scopes ++ scopes,
          [%{"path" => "lib", "kind" => "glob"}],
          [%{"path" => "lib", "kind" => "file", "extra" => 1}],
          Enum.map(1..65, &%{"path" => "file#{&1}", "kind" => "file"})
        ] do
      assert {:error, :invalid_plan} =
               Protocol.plan(JSON.encode!(Map.put(@plan, "file_scopes", invalid)))
    end

    for path <- [
          "",
          "/lib",
          "lib/",
          "lib//a",
          ".",
          "../lib",
          "a/./b",
          "a/../b",
          ".git/config",
          ".GIT/config",
          "lib/*",
          "a?b",
          "a[b]",
          "a{b}",
          "C:lib",
          "a\\b",
          "a\nb",
          "a\0b",
          "a\x7fb",
          " a",
          "a ",
          String.duplicate("a", 1025)
        ] do
      assert {:error, :invalid_file_scopes} =
               FileScopes.validate([%{"path" => path, "kind" => "file"}])
    end

    duplicate =
      ~s({"summary":"ok","steps":["step"],"acceptance":["criterion"],"file_scopes":[{"path":"a","path":"b","kind":"file"}]})

    assert {:error, :invalid_plan} = Protocol.plan(duplicate)
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

  test "fresh integration review preserves both complete diffs and refuses oversized combined evidence" do
    input = %{
      "specification" => "Saved source",
      "plan" => @plan,
      "original_candidate" => String.duplicate("a", 40),
      "target_commit" => String.duplicate("b", 40),
      "candidate_commit" => String.duplicate("c", 40),
      "diff" => "original base diff",
      "target_diff" => "current target diff",
      "check_output" => %{"stdout" => "complete output", "stderr" => "complete errors"}
    }

    for kind <- [:merge_review, :claude_merge_review] do
      assert {:ok, prompt} = Protocol.prompt(kind, input)
      assert prompt =~ "fresh integration review"
      [_, serialized] = String.split(prompt, "BOSS delivery input (JSON):\n", parts: 2)
      assert JSON.decode!(serialized) == input

      assert {:error, :input_too_large} =
               Protocol.prompt(kind, %{
                 input
                 | "diff" => String.duplicate("x", 600_000),
                   "target_diff" => String.duplicate("y", 600_000)
               })
    end
  end
end
