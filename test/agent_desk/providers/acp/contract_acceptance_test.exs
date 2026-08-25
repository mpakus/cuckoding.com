defmodule AgentDesk.Providers.ACP.ContractAcceptanceTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.Cursor
  alias AgentDesk.Providers.Event

  @contract_fixture "priv/provider_fixtures/cursor/contract.jsonl"
  @malformed_fixture "priv/provider_fixtures/cursor/malformed.jsonl"

  test "Cursor fixture covers auth, permission, fs read, and cancellation contracts" do
    [initialize, authenticated, session, permission, fs_read, cancelled] =
      fixture_lines(@contract_fixture)

    client = Cursor.init_decode()

    {initialize_request, client} = encode(client, :initialize)
    assert json(initialize_request)["method"] == "initialize"

    assert get_in(json(initialize_request), ["params", "clientCapabilities", "fs", "readTextFile"])

    assert {:ok, [%Event{type: :initialize_result} = initialized], client} =
             Cursor.decode_line(initialize, client)

    assert [%{"id" => "cursor-login"}] = initialized.payload["authMethods"]

    {auth_request, client} = encode(client, {:authenticate, "cursor-login"})
    assert json(auth_request)["method"] == "authenticate"
    assert get_in(json(auth_request), ["params", "methodId"]) == "cursor-login"

    assert {:ok, [%Event{type: :authenticated}], client} =
             Cursor.decode_line(authenticated, client)

    {session_request, client} =
      encode(
        client,
        {:start_session, "/tmp/worktree",
         [%{"name" => "agentdesk-hub", "command" => "elixir", "args" => [], "env" => []}]}
      )

    assert json(session_request)["method"] == "session/new"

    assert get_in(json(session_request), ["params", "mcpServers", Access.at(0), "name"]) ==
             "agentdesk-hub"

    assert {:ok, [%Event{type: :session_ready}], client} =
             Cursor.decode_line(session, client)

    assert {:ok, [%Event{type: :approval_requested} = approval], client} =
             Cursor.decode_line(permission, client)

    assert approval.payload["request_id"] == "9001"
    assert approval.payload["summary"] == "Read README"

    {approval_response, client} = encode(client, {:approve, "9001", "allow"})
    assert get_in(json(approval_response), ["result", "outcome", "outcome"]) == "selected"

    assert {:ok, [%Event{type: :client_request} = request], client} =
             Cursor.decode_line(fs_read, client)

    assert request.payload == %{
             "method" => "fs/read_text_file",
             "params" => %{
               "limit" => 20,
               "line" => 1,
               "path" => "/tmp/worktree/README.md"
             },
             "request_id" => "9002"
           }

    {fs_response, client} =
      encode(client, {:jsonrpc_result, "9002", %{"content" => "# Cuckoding"}})

    assert get_in(json(fs_response), ["result", "content"]) == "# Cuckoding"

    {cancel_request, client} = encode(client, :interrupt)
    assert json(cancel_request)["method"] == "session/cancel"
    assert get_in(json(cancel_request), ["params", "sessionId"]) == "cursor-contract-session"
    assert {:ok, [], _client} = Cursor.decode_line(cancelled, client)
  end

  test "malformed ACP fixture is a decoder error" do
    [malformed] = fixture_lines(@malformed_fixture)

    assert {:error, {:invalid_json, _reason}} =
             Cursor.decode_line(malformed, Cursor.init_decode())
  end

  defp encode(client, action) do
    {:ok, payload, client} = Cursor.encode(action, client)
    {IO.iodata_to_binary(payload), client}
  end

  defp fixture_lines(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
  end

  defp json(payload) do
    payload
    |> String.trim()
    |> Jason.decode!()
  end
end
