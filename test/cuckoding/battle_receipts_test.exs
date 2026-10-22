defmodule Cuckoding.Battles.ReceiptsTest do
  use Cuckoding.DataCase
  alias Cuckoding.Battles.{Attempt, Receipts}

  defp attempt(stage, task_id \\ Ecto.UUID.generate()) do
    envelope = %{
      "battle_id" => Ecto.UUID.generate(),
      "request_id" => Ecto.UUID.generate(),
      "task_id" => task_id,
      "stage" => stage,
      "criteria_sha256" => String.duplicate("a", 64)
    }

    %Attempt{
      id: envelope["request_id"],
      battle_id: envelope["battle_id"],
      task_id: task_id,
      stage: stage,
      request:
        Map.merge(envelope, %{
          "snapshot" => %{"version" => "arena-loop-v2", "checks" => []},
          "task_context" => %{"candidate_sha" => String.duplicate("b", 40)},
          "context" => %{"head" => String.duplicate("c", 40)}
        })
    }
  end

  test "the public boundary rejects foreign envelopes, raw data and oversized receipts" do
    attempt = attempt("integrate")
    envelope = Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))
    receipt = Map.merge(envelope, %{"status" => "failed", "reason" => "connection_lost"})
    assert Receipts.bound?(attempt, receipt)
    assert Receipts.payload_valid?(attempt, receipt)

    for key <- Map.keys(envelope) do
      refute Receipts.bound?(attempt, Map.put(receipt, key, "foreign"))
    end

    refute Receipts.bound?(attempt, nil)
    refute Receipts.bound?(attempt, Map.put(receipt, "raw", "provider-canary"))
    refute Receipts.bound?(attempt, Map.put(receipt, "summary", String.duplicate("x", 131_072)))
    closure = Map.put(receipt, "provider_closure", %{"status" => "closed"})
    refute Receipts.bound?(attempt, closure)
    assert Receipts.bound?(attempt, closure, ["provider_closure"])
  end

  test "task and final candidate checks keep distinct frozen heads and empty-scope rules" do
    task = attempt("integrate")

    payload = %{
      "status" => "integrated",
      "candidate_sha" => String.duplicate("b", 40),
      "head" => String.duplicate("b", 40),
      "native_battle" => %{}
    }

    assert Receipts.payload_valid?(task, payload)

    refute Receipts.payload_valid?(
             task,
             Map.put(payload, "candidate_sha", String.duplicate("c", 40))
           )

    refute Receipts.payload_valid?(task, Map.put(payload, "head", String.duplicate("c", 40)))
    final = attempt("final_checks", nil)

    refute Receipts.payload_valid?(final, %{
             "status" => "passed",
             "candidate_sha" => String.duplicate("c", 40),
             "checks" => []
           })

    admission = attempt("admission", nil)

    admitted = %{
      "status" => "admitted",
      "head" => String.duplicate("c", 40),
      "native_battle" => %{},
      "resolved_checks" => []
    }

    assert Receipts.payload_valid?(admission, admitted)
    historical = put_in(admission.request["snapshot"]["version"], "arena-loop-v1")
    refute Receipts.payload_valid?(historical, admitted)
  end
end
