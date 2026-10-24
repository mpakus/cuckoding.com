defmodule Cuckoding.BattleChecksTest do
  use ExUnit.Case, async: true
  alias Cuckoding.BattleChecks

  defp receipt do
    %{
      "status" => "passed",
      "request_id" => Ecto.UUID.generate(),
      "contract" => "codex-check-single-process-v1",
      "cleanup_verified" => true,
      "candidate_sha" => String.duplicate("a", 40),
      "checks" => [
        %{
          "id" => Ecto.UUID.generate(),
          "status" => "passed",
          "exit_code" => 0,
          "stdout_sha256" => String.duplicate("b", 64),
          "stdout_bytes" => 3,
          "pid" => 321,
          "spawned_at_ms" => 1_800_000_000_000,
          "elapsed_ms" => 42,
          "cleanup_verified" => true,
          "child_pid" => 322,
          "child_start_seconds" => 1_800_000_000,
          "child_start_microseconds" => 100
        }
      ]
    }
  end

  test "passed checks retain candidate, request and owned process identities without raw output" do
    result = receipt()
    assert BattleChecks.normalize(Jason.encode!(result)) == result
    changed = put_in(result, ["checks", Access.at(0), "stdout"], "private bytes")
    assert %{"status" => "invalid_output"} = BattleChecks.normalize(Jason.encode!(changed))
  end

  test "partial cancelled receipts preserve cleanup uncertainty and completed check evidence" do
    result = Map.merge(receipt(), %{"status" => "cancelled", "cleanup_verified" => false})
    assert BattleChecks.normalize(Jason.encode!(result)) == result
    changed = put_in(result, ["checks", Access.at(0), "child_start_seconds"], nil)
    assert %{"status" => "invalid_output"} = BattleChecks.normalize(Jason.encode!(changed))
  end

  test "a missing request identity, legacy grant or duplicate check cannot become fresh evidence" do
    for result <- [
          Map.delete(receipt(), "request_id"),
          Map.put(receipt(), "contract", "codex-check-sandbox-v1"),
          Map.put(receipt(), "contract", "guest-check-v1"),
          Map.put(receipt(), "contract", "isolated-guest-check-v1"),
          Map.put(receipt(), "contract", "isolated-check-image-v1"),
          Map.update!(receipt(), "checks", &(&1 ++ &1))
        ] do
      assert %{"status" => "invalid_output"} = BattleChecks.normalize(Jason.encode!(result))
    end
  end
end
