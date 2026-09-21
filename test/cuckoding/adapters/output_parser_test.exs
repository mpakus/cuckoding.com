defmodule Cuckoding.Adapters.OutputParserTest do
  use ExUnit.Case, async: true

  alias Cuckoding.Adapters.OutputParser
  alias Cuckoding.Adapters.Types

  setup do
    root = Path.join(System.tmp_dir!(), "cuckoding-output-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "extracts the final structured value from each supported JSONL shape", %{root: root} do
    output = %{"tasks" => [%{"title" => "One"}]}

    codex =
      write_jsonl(root, "codex.jsonl", [
        %{"type" => "turn.started"},
        %{
          "type" => "item.completed",
          "item" => %{"type" => "agent_message", "text" => Jason.encode!(output)}
        }
      ])

    claude =
      write_jsonl(root, "claude.jsonl", [
        %{"type" => "result", "subtype" => "success", "structured_output" => output}
      ])

    cursor =
      write_jsonl(root, "cursor.jsonl", [
        %{"type" => "result", "subtype" => "success", "result" => Jason.encode!(output)}
      ])

    assert {:ok, ^output} = OutputParser.extract("codex", %{artifact_path: codex})
    assert {:ok, ^output} = OutputParser.extract("claude_code", %{artifact_path: claude})
    assert {:ok, ^output} = OutputParser.extract("cursor_agent", %{artifact_path: cursor})
    assert {:ok, ^output} = OutputParser.extract("fake", %{structured_output: output})
  end

  test "accepts the Codex stdin prelude and keeps other non-JSON output invalid", %{root: root} do
    output = %{"tasks" => [%{"title" => "One"}]}
    valid = Path.join(root, "codex-with-prelude.jsonl")

    File.write!(
      valid,
      "Reading additional input from stdin...\n" <>
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "agent_message", "text" => Jason.encode!(output)}
        }) <> "\n"
    )

    assert {:ok, ^output} = OutputParser.extract("codex", %{artifact_path: valid})

    File.write!(valid, "unexpected output\n" <> File.read!(valid))

    assert {:error, %Types.Error{code: :malformed_output}} =
             OutputParser.extract("codex", %{artifact_path: valid})
  end

  test "keeps public agent messages and excludes tool output and hidden reasoning", %{root: root} do
    path =
      write_jsonl(root, "messages.jsonl", [
        %{
          "type" => "item.completed",
          "item" => %{
            "id" => "one",
            "type" => "agent_message",
            "text" => Jason.encode!(%{"summary" => "First update"})
          }
        },
        %{
          "type" => "item.completed",
          "item" => %{
            "id" => "tool",
            "type" => "command_execution",
            "command" => "echo private",
            "aggregated_output" => "private"
          }
        },
        %{
          "type" => "item.completed",
          "item" => %{"id" => "hidden", "type" => "reasoning", "text" => "private thought"}
        },
        %{
          "type" => "item.completed",
          "item" => %{
            "id" => "two",
            "type" => "agent_message",
            "text" => Jason.encode!(%{"summary" => "# Final specification"})
          }
        }
      ])

    assert {:ok, events} = OutputParser.activity_events("codex", %{artifact_path: path})
    assert Enum.map(events, & &1.public_summary) == ["First update", "# Final specification"]
    assert Enum.all?(events, &(&1.trust == :untrusted))
    refute inspect(events) =~ "private"
  end

  test "reads only terminal usage from the redacted JSONL and retains reported cost", %{
    root: root
  } do
    codex =
      write_jsonl(root, "codex-usage.jsonl", [
        %{"type" => "item.completed", "item" => %{"type" => "reasoning", "text" => "private"}},
        %{"type" => "turn.completed", "usage" => %{"input_tokens" => 12}}
      ])

    claude =
      write_jsonl(root, "claude-usage.jsonl", [
        %{
          "type" => "result",
          "subtype" => "success",
          "request_id" => "request-test",
          "usage" => %{"input_tokens" => 8},
          "total_cost_usd" => 0.02
        }
      ])

    cursor =
      write_jsonl(root, "cursor-usage.jsonl", [
        %{"type" => "result", "subtype" => "success", "usage" => %{"inputTokens" => 7}}
      ])

    assert {:ok, [{_, %{"input_tokens" => 12}}]} =
             OutputParser.usage_events("codex", %{artifact_path: codex})

    assert {:ok, [{_, %{"input_tokens" => 8, "total_cost_usd" => 0.02}}]} =
             OutputParser.usage_events("claude_code", %{artifact_path: claude})

    assert {:ok, [{_, %{"inputTokens" => 7}}]} =
             OutputParser.usage_events("cursor_agent", %{artifact_path: cursor})

    refute inspect(OutputParser.usage_events("codex", %{artifact_path: codex})) =~ "private"

    malformed =
      write_jsonl(root, "bad-usage.jsonl", [%{"type" => "turn.completed", "usage" => "bad"}])

    assert {:error, %Types.Error{code: :malformed_usage}} =
             OutputParser.usage_events("codex", %{artifact_path: malformed})
  end

  test "rejects malformed or non-regular output", %{root: root} do
    malformed = Path.join(root, "malformed.jsonl")
    File.write!(malformed, "not-json\n")

    assert {:error, %Types.Error{code: :malformed_output}} =
             OutputParser.extract("codex", %{artifact_path: malformed})

    assert {:error, %Types.Error{code: :structured_output_missing}} =
             OutputParser.extract("codex", %{artifact_path: root})
  end

  defp write_jsonl(root, name, rows) do
    path = Path.join(root, name)
    File.write!(path, Enum.map_join(rows, "\n", &Jason.encode!/1) <> "\n")
    path
  end
end
