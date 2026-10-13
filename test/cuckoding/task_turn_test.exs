defmodule Cuckoding.TaskTurnTest do
  use ExUnit.Case, async: true
  alias Cuckoding.{Codex, TaskTurn}

  defp receipt do
    %{
      "status" => "task_finished",
      "request_id" => Ecto.UUID.generate(),
      "grant" => "host-task-tools-v1",
      "access" => "read",
      "requested_model" => "test-model",
      "observed_model" => "test-model",
      "effort" => "low",
      "thread_id" => "review-session",
      "turn_id" => "review-turn",
      "report" => %{"outcome" => "changes_requested", "summary" => "Missing criterion."},
      "tools" => [
        %{
          "call_id" => "read-one",
          "tool" => "read_file",
          "status" => "completed",
          "sha256" => String.duplicate("a", 64)
        }
      ]
    }
  end

  test "closed public report retains review findings and rejects foreign tool fields" do
    original = receipt()
    assert TaskTurn.normalize(Jason.encode!(original)) == original

    assert TaskTurn.normalize(Jason.encode!(Map.put(original, "raw_provider", "private-canary"))) ==
             original

    for invalid <- [
          put_in(original, ["tools", Access.at(0), "command"], "private-canary"),
          put_in(original, ["tools", Access.at(0), "tool"], "shell"),
          Map.put(original, "tools", original["tools"] ++ original["tools"]),
          put_in(original, ["report", "outcome"], "force_complete"),
          put_in(original, ["report", "summary"], String.duplicate("x", 4001)),
          Map.put(original, "grant", "anything")
        ] do
      assert TaskTurn.normalize(Jason.encode!(invalid)) == %{"status" => "invalid_output"}
    end
  end

  test "Cursor keeps the requested alias and native base model parameters separately" do
    result =
      receipt()
      |> Map.merge(%{
        "transport" => "cursor-acp-v1",
        "effort" => nil,
        "runtime_model" => "grok-4.6",
        "runtime_parameters" => %{"effort" => "xhigh", "fast" => "true"}
      })

    assert TaskTurn.normalize(Jason.encode!(result)) == result

    for invalid <- [
          Map.delete(result, "runtime_model"),
          Map.delete(result, "runtime_parameters"),
          Map.put(result, "transport", "unknown"),
          Map.put(result, "runtime_parameters", %{"raw" => "private account data"})
        ] do
      assert TaskTurn.normalize(Jason.encode!(invalid)) == %{"status" => "invalid_output"}
    end

    assert Cuckoding.Cursor.run_task(%{}, "unused", "unused", %{}, fn -> false end) == %{
             "status" => "cancelled"
           }
  end

  test "cancelled turns retain normalized effects but no successful report" do
    result =
      receipt() |> Map.put("status", "cancelled") |> Jason.encode!() |> TaskTurn.normalize()

    assert result["status"] == "cancelled"
    assert length(result["tools"]) == 1
    refute result["report"]

    assert Codex.run_task(%{}, "unused", "unused", %{}, fn -> false end) == %{
             "status" => "cancelled"
           }
  end

  test "candidate changes are the exact final host edit receipts" do
    sha = String.duplicate("b", 64)

    result =
      receipt()
      |> Map.merge(%{
        "access" => "write",
        "tools" => [
          %{
            "call_id" => "edit",
            "tool" => "edit_file",
            "status" => "completed",
            "path" => "src/main.ex",
            "sha256" => sha
          }
        ],
        "changes" => [%{"path" => "src/main.ex", "sha256" => sha}]
      })

    assert TaskTurn.normalize(Jason.encode!(result)) == result

    for invalid <- [
          Map.put(result, "changes", []),
          Map.put(result, "access", "read"),
          put_in(result, ["changes", Access.at(0), "sha256"], String.duplicate("c", 64)),
          put_in(result, ["changes", Access.at(0), "path"], "../outside"),
          put_in(result, ["tools", Access.at(0), "path"], ".git/config")
        ] do
      assert TaskTurn.normalize(Jason.encode!(invalid)) == %{"status" => "invalid_output"}
    end
  end
end
