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

  test "unknown Cursor extension methods become diagnostics and can be rejected" do
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
                type: :provider_error,
                payload: %{"unsupported_method" => "cursor/askQuestion"}
              }
            ], client} = Client.decode_line(client, line)

    assert {:ok, encoded, _} = Client.encode(client, {:reject_method, 44, "cursor/askQuestion"})
    assert encoded =~ "Unsupported method"
  end

  defp encode_request(client, action) do
    {:ok, iodata, client} = Client.encode(client, action)
    {IO.iodata_to_binary(iodata), client}
  end
end
