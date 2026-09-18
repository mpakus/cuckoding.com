defmodule Cuckoding.Workflows.GateEvaluatorTest do
  use ExUnit.Case, async: true

  alias Cuckoding.Workflows.GateEvaluator

  test "failed QA returns a structured finding" do
    bundle = bundle(%{"status" => "failed", "passed" => 3, "failed" => 1})

    assert {:error, %{"outcome" => "failed", "findings" => [finding]}} =
             GateEvaluator.evaluate(bundle)

    assert finding["severity"] == "error"
    assert finding["category"] == "qa"
    assert finding["summary"] == "QA command failed: mix test"
    assert finding["evidence"]["failed"] == 1
  end

  test "malformed artifact descriptors fail closed" do
    malformed = put_in(bundle(), ["artifacts", Access.at(0), "path"], "../secret")

    assert {:error, %{"findings" => [finding]}} = GateEvaluator.evaluate(malformed)
    assert finding["severity"] == "blocker"
    assert finding["category"] == "artifact_schema"
  end

  defp bundle(test_result \\ %{}) do
    sha = String.duplicate("a", 64)

    %{
      "schema_version" => 1,
      "run_id" => "run",
      "branch" => "feature/test",
      "base_sha" => String.duplicate("1", 40),
      "head_sha" => String.duplicate("2", 40),
      "artifacts" => [
        %{"type" => "qa_report", "path" => "qa.md", "sha256" => sha}
      ],
      "tests" => [
        Map.merge(
          %{"command" => "mix test", "status" => "passed", "passed" => 4, "failed" => 0},
          test_result
        )
      ],
      "findings" => [],
      "knowledge_citations" => [
        %{"path" => "knowledge/candidates/test.md", "sha256" => sha}
      ]
    }
  end
end
