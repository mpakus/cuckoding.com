defmodule AgentDesk.Providers.JSONRPCTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.JSONRPC

  test "correlates responses to the originating method" do
    {req, state} = JSONRPC.request(JSONRPC.new(), "initialize", %{})
    assert req =~ "initialize"

    {:ok, decoded} = Jason.decode(String.trim(req))
    id = decoded["id"]
    line = Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => %{"ok" => true}})

    assert {:ok, {:response, ^id, %{"ok" => true}, "initialize"}, state} =
             JSONRPC.decode_line(state, line)

    assert state.pending == %{}
  end

  test "classifies server-initiated requests and notifications" do
    state = JSONRPC.new()

    request =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 9,
        "method" => "session/request_permission",
        "params" => %{}
      })

    assert {:ok, {:request, 9, "session/request_permission", %{}}, _} =
             JSONRPC.decode_line(state, request)

    note =
      Jason.encode!(%{"jsonrpc" => "2.0", "method" => "session/update", "params" => %{"a" => 1}})

    assert {:ok, {:notification, "session/update", %{"a" => 1}}, _} =
             JSONRPC.decode_line(state, note)
  end

  test "accepts Codex app-server frames that omit the jsonrpc header" do
    {req, state} = JSONRPC.request(JSONRPC.new(header: false), "initialize", %{})
    refute req =~ "jsonrpc"
    assert {:ok, decoded} = Jason.decode(String.trim(req))
    id = decoded["id"]

    line = Jason.encode!(%{"id" => id, "result" => %{"userAgent" => "codex"}})

    assert {:ok, {:response, ^id, %{"userAgent" => "codex"}, "initialize"}, _} =
             JSONRPC.decode_line(state, line)
  end
end
