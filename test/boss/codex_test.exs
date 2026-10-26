defmodule Boss.CodexTest do
  use ExUnit.Case, async: true
  alias Boss.Agents.Codex

  test "split JSONL retains only allowlisted metadata and requires a complete turn" do
    data =
      ~s({"type":"turn.started"}\n{"type":"item.completed","item":{"text":"SECRET_SENTINEL"}}\n{"type":"turn.completed","usage":{"input_tokens":3,"key":"SECRET_SENTINEL"}}\n)

    state =
      Enum.reduce(:binary.bin_to_list(data), Codex.new(), fn byte, state ->
        Codex.feed(state, {:stdout, <<byte>>})
      end)

    assert Codex.complete?(state)
    summary = Codex.summary(state)
    assert summary["event_count"] == 3
    assert summary["usage"] == %{"input_tokens" => 3}
    refute inspect(summary) =~ "SECRET_SENTINEL"
    refute Codex.complete?(Codex.feed(state, {:stdout, ~s({"type":"turn.started"}\n)}))
  end

  test "bad, oversized, incomplete and failed protocol cannot complete" do
    for data <- [
          "not json\n",
          "[]\n",
          ~s({"type":"turn.completed"}\n),
          ~s({"type":"turn.started"}\n{"type":"turn.failed"}\n),
          ~s({"type":"turn.started"}\n{"type":"turn.completed"}),
          String.duplicate("x", 262_145)
        ] do
      refute Codex.complete?(Codex.feed(Codex.new(), {:stdout, data}))
    end

    state = Codex.feed(Codex.new(), {:stderr, "SECRET_SENTINEL"})
    assert state.stderr_bytes == 15
    refute inspect(state) =~ "SECRET_SENTINEL"
  end

  test "bounded event history, source limits and sandboxed stdin invocation" do
    data = String.duplicate(~s({"type":"item.updated"}\n), 100)
    state = Codex.feed(Codex.new(), {:stdout, data})
    assert length(state.events) == 20
    assert state.count == 100
    assert {:ok, prompt} = Codex.prompt("# Saved exact source\n")
    assert String.ends_with?(prompt, "# Saved exact source\n")
    assert {:error, :input_too_large} = Codex.prompt(String.duplicate("x", 1_048_576))
    assert "workspace-write" in Codex.args()
    assert List.last(Codex.args()) == "-"
    refute Enum.any?(Codex.args(), &String.contains?(&1, "bypass"))
  end
end
