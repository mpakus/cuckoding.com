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
