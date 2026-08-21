defmodule AgentDesk.CanonicalTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Canonical

  test "hashes maps independently of key order and atom vs string keys" do
    left = Canonical.hash(%{task_id: "a", reason: "do it"})
    right = Canonical.hash(%{"reason" => "do it", "task_id" => "a"})

    assert left == right
    assert String.match?(left, ~r/^[0-9a-f]{64}$/)
  end

  test "different payloads produce different hashes" do
    refute Canonical.hash(%{reason: "a"}) == Canonical.hash(%{reason: "b"})
  end
end
