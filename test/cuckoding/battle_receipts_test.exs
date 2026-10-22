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

  test "combination evidence is exact to the new attempt, both bases and its original writer" do
    item = attempt("combine")
    preparation = %{"key" => Ecto.UUID.generate(), "head" => String.duplicate("d", 40)}
    original = %{"key" => Ecto.UUID.generate()}

    item = %{
      item
      | request:
          item.request
          |> put_in(["snapshot", "parallelism"], "parallel-waves-v1")
          |> put_in(["task_context", "preparation"], preparation)
          |> put_in(["task_context", "native_candidate"], original)
    }

    native = %{
      "status" => "candidate_combined",
      "key" => item.id,
      "battle_key" => item.battle_id,
      "worktree_key" => preparation["key"],
      "task_candidate_key" => original["key"],
      "base" => item.request["context"]["head"],
      "task_base" => preparation["head"],
      "candidate" => String.duplicate("e", 40),
      "tree" => String.duplicate("f", 40),
      "manifest_sha256" => String.duplicate("a", 64)
    }

    receipt = %{
      "status" => "combined",
      "candidate_sha" => native["candidate"],
      "native_candidate" => native
    }

    assert Receipts.payload_valid?(item, receipt)

    for field <- ~w(key battle_key worktree_key task_candidate_key) do
      refute Receipts.payload_valid?(
               item,
               put_in(receipt, ["native_candidate", field], Ecto.UUID.generate())
             )
    end

    for field <- ~w(base task_base candidate) do
      refute Receipts.payload_valid?(
               item,
               put_in(receipt, ["native_candidate", field], String.duplicate("b", 40))
             )
    end

    historical = %{
      item
      | request: Map.update!(item.request, "snapshot", &Map.delete(&1, "parallelism"))
    }

    refute Receipts.payload_valid?(historical, receipt)
  end
end
