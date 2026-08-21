defmodule AgentDesk.Providers.FixtureFilesTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.ACP.Client
  alias AgentDesk.Providers.Claude
  alias AgentDesk.Providers.Codex.AppServer

  test "codex, claude, cursor, and opencode fixtures decode through their adapters" do
    assert decode_jsonrpc(AppServer, "priv/provider_fixtures/codex/handshake.jsonl")
           |> Enum.any?(&(&1.type == :session_ready))

    assert decode_lines(Claude, "priv/provider_fixtures/claude/stream.jsonl")
           |> Enum.any?(&(&1.type == :session_ready))

    assert decode_jsonrpc_client("cursor", "priv/provider_fixtures/cursor/handshake.jsonl")
           |> Enum.any?(&(&1.type == :session_ready))

    assert decode_jsonrpc_client("opencode", "priv/provider_fixtures/opencode/handshake.jsonl")
           |> Enum.any?(&(&1.type == :message_delta))
  end

  defp decode_jsonrpc(module, path) do
    {events, _} =
      Enum.reduce(jsonl(path), {[], module.init_decode()}, fn line, {acc, state} ->
        case module.decode_line(line, state) do
          {:ok, more, state} -> {acc ++ more, state}
          {:error, _} -> {acc, state}
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

  defp decode_jsonrpc_client(provider, path) do
    {events, _} =
      Enum.reduce(jsonl(path), {[], Client.new(provider)}, fn line, {acc, client} ->
        case Client.decode_line(client, line) do
          {:ok, more, client} -> {acc ++ more, client}
          {:error, _} -> {acc, client}
        end
      end)

    events
  end

  defp jsonl(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&(&1 == ""))
  end
end
