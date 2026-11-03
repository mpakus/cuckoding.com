defmodule Boss.DeliveryDiagnosticsTest do
  use ExUnit.Case, async: true
  alias Boss.Deliveries.Diagnostics

  test "old blocked receipts show the review finding without rewriting history" do
    reason = "The three-cycle implementation/check/review budget is exhausted."

    steps = [
      %{
        kind: "review",
        receipt: %{
          "report" => %{
            "verdict" => "changes_requested",
            "issues" => [
              %{"message" => "The response reads beyond the byte limit.\nStop at the ceiling."}
            ]
          }
        }
      }
    ]

    assert Diagnostics.attention(reason, steps) =~ "Stop at the ceiling."
    assert Diagnostics.attention(reason, steps) =~ "Next: fix"
    assert Diagnostics.attention("Original reason", steps) == "Original reason"
  end

  test "failure comments stay bounded and show recovery without raw output" do
    text = Diagnostics.clarification(%{"issues" => [%{"message" => String.duplicate("ёж", 500)}]})
    assert String.valid?(text) and byte_size(text) < 1000
    assert text =~ "Next: clarify"

    assert Diagnostics.step_failure("check", %{
             "outcome" => "timeout",
             "output" => "private output"
           }) ==
             "Checks timed out. Next: inspect the retained workspace and address slow or interactive work before retrying."
  end
end
