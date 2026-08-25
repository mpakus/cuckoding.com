defmodule AgentDesk.Providers.ACP.ClientTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.ACP.Client
  alias AgentDesk.Providers.Event

  test "normalizes Cursor and OpenCode session updates through the shared client" do
    cursor = Client.new("cursor")
    opencode = Client.new("opencode")

    {init, cursor} = encode_request(cursor, :initialize)
    {init2, opencode} = encode_request(opencode, :initialize)
    refute init == ""
    refute init2 == ""
    assert init =~ "clientCapabilities"

    update =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "session/update",
        "params" => %{
          "update" => %{
            "sessionUpdate" => "agent_message_chunk",
            "content" => %{"type" => "text", "text" => "hi"}
          }
        }
      })

    assert {:ok, [%Event{type: :message_delta, payload: %{"text" => "hi"}}], _} =
             Client.decode_line(cursor, update)

    assert {:ok, [%Event{type: :message_delta}], _} = Client.decode_line(opencode, update)
  end

  test "unknown Cursor extension methods are client requests, not session failures" do
    client = Client.new("cursor")

    line =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 44,
        "method" => "cursor/askQuestion",
        "params" => %{"prompt" => "choose"}
      })

    assert {:ok,
            [
              %Event{
                type: :client_request,
                payload: %{"method" => "cursor/askQuestion", "unsupported" => true}
              }
            ], client} = Client.decode_line(client, line)

    assert {:ok, encoded, _} = Client.encode(client, {:reject_method, 44, "cursor/askQuestion"})
    assert encoded =~ "Unsupported method"
  end

  test "initialize then session/new can include MCP servers and skips configure_mcp" do
    client = Client.new("cursor")
    {_init, client} = encode_request(client, :initialize)
    servers = [%{"name" => "agentdesk-hub", "command" => "elixir", "args" => [], "env" => []}]
    {:ok, start, client} = Client.encode(client, {:start_session, "/tmp/wt", servers})
    assert start =~ "session/new"
    assert start =~ "agentdesk-hub"
    assert {:ok, "", _} = Client.encode(client, {:configure_mcp, "/tmp/mcp.json"})
  end

  test "fs/read_text_file becomes a client request" do
    client = Client.new("cursor")

    line =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "fs/read_text_file",
        "params" => %{"path" => "/tmp/wt/README.md"}
      })

    assert {:ok,
            [
              %Event{
                type: :client_request,
                payload: %{"method" => "fs/read_text_file", "request_id" => "7"}
              }
            ], _} = Client.decode_line(client, line)
  end

  defp encode_request(client, action) do
    {:ok, iodata, client} = Client.encode(client, action)
    {IO.iodata_to_binary(iodata), client}
  end
end
