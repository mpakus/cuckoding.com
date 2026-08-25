defmodule AgentDesk.Providers.FixtureFilesTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.Claude
  alias AgentDesk.Providers.Codex.AppServer
  alias AgentDesk.Providers.Cursor
  alias AgentDesk.Providers.OpenCode

  test "codex, claude, cursor, and opencode fixtures decode through their adapters" do
    assert decode_jsonrpc(AppServer, "priv/provider_fixtures/codex/handshake.jsonl")
           |> Enum.any?(&(&1.type == :session_ready))

    assert decode_lines(Claude, "priv/provider_fixtures/claude/stream.jsonl")
           |> Enum.any?(&(&1.type == :session_ready))

    assert decode_jsonrpc(Cursor, "priv/provider_fixtures/cursor/handshake.jsonl")
           |> Enum.any?(&(&1.type == :session_ready))

    assert decode_jsonrpc(OpenCode, "priv/provider_fixtures/opencode/handshake.jsonl")
           |> Enum.any?(&(&1.type == :message_delta))
  end

  test "fixture decoding fails instead of discarding decoder errors" do
    path =
      Path.join(
        System.tmp_dir!(),
        "agentdesk-invalid-fixture-#{System.unique_integer([:positive])}.jsonl"
      )

    File.write!(path, "{not-json\n")
    on_exit(fn -> File.rm(path) end)

    assert_raise RuntimeError, ~r/fixture decoder failed.*invalid_json/s, fn ->
      decode_jsonrpc(Cursor, path)
    end
  end

  defp decode_jsonrpc(module, path) do
    {events, _} =
      Enum.reduce(jsonl(path), {[], module.init_decode()}, fn line, {acc, state} ->
        case module.decode_line(line, state) do
          {:ok, more, state} -> {acc ++ more, state}
          {:error, reason} -> fixture_error!(path, line, reason)
        end
      end)

    events
  end

  defp decode_lines(module, path) do
    {events, _} =
      Enum.reduce(jsonl(path), {[], module.init_decode()}, fn line, {acc, state} ->
        {:ok, more, state} = module.decode_line(line, state)
        {acc ++ more, state}
      end)

    events
  end

  defp jsonl(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  defp fixture_error!(path, line, reason) do
    raise "fixture decoder failed for #{path}: #{inspect(reason)} while decoding #{inspect(line)}"
  end
end
