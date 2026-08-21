defmodule AgentDesk.CorrelationTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Correlation

  test "starts a workflow correlation and follows causation" do
    parent = Correlation.new(context_id: "ctx-1", idempotency_key: "k1")
    child = Correlation.follow(parent, "evt-1")

    assert parent.correlation_id
    assert child.correlation_id == parent.correlation_id
    assert child.context_id == "ctx-1"
    assert child.causation_id == "evt-1"
    assert is_nil(child.idempotency_key)
  end
end
