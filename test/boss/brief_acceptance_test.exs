defmodule Boss.Projects.BriefAcceptanceTest do
  use ExUnit.Case, async: true
  alias Boss.Projects.BriefAcceptance

  test "coverage comes from original nonblank lines in stable source order" do
    assert BriefAcceptance.criteria(%{"z.md" => "Third", "a.md" => "# Product\n\nSecond"}) ==
             ["S1:L1", "S1:L3", "S2:L1"]

    assert BriefAcceptance.criteria(%{"doc.md" => " \t\n"}) == []
  end

  test "long briefs retain the last source line within the review protocol limit" do
    text = Enum.map_join(1..41, "\n", &Integer.to_string/1)
    criteria = BriefAcceptance.criteria(%{"doc.md" => text})
    assert length(criteria) <= 20
    assert hd(criteria) == "S1:L1..S1:L3"
    assert List.last(criteria) == "S1:L40..S1:L41"
  end

  test "a task plan cannot discard a whole-brief criterion" do
    input = %{"brief_criteria" => ["S1:L1", "S1:L2"]}

    report =
      JSON.encode!(%{"steps" => ["Implement"], "summary" => "Plan", "acceptance" => ["S1:L1"]})

    assert {:error, _} = BriefAcceptance.decode_plan(report, nil, input)
  end
end
