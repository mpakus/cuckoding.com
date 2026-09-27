defmodule Cuckoding.Adapters.ACP.WireTest do
  use ExUnit.Case, async: true
  alias Cuckoding.Adapters.ACP.Wire

  test "correlates out-of-order replies with requests across fragmented UTF-8 frames" do
    assert {:ok, wire, 1, request} =
             Wire.request(%Wire{}, "initialize", %{"protocolVersion" => 1})

    assert Jason.decode!(request)["jsonrpc"] == "2.0"
    assert {:ok, wire, 2, _} = Wire.request(wire, "session/new", %{"cwd" => "/worktree"})

    bytes =
      frame(%{"id" => 2, "result" => %{"sessionId" => "session-λ"}}) <>
        frame(%{"method" => "session/update", "params" => %{"sessionId" => "session-λ"}}) <>
        frame(%{"id" => 1, "result" => %{"protocolVersion" => 1}})

    {wire, messages} =
      for <<byte <- bytes>>, reduce: {wire, []} do
        {wire, messages} ->
          assert {:ok, wire, decoded} = Wire.feed(wire, <<byte>>)
          {wire, messages ++ decoded}
      end

    assert [
             {:response, 2, "session/new", {:ok, %{"sessionId" => "session-λ"}}},
             {:notification, "session/update", %{"sessionId" => "session-λ"}},
             {:response, 1, "initialize", {:ok, %{"protocolVersion" => 1}}}
           ] = messages

    assert :ok = Wire.finish(wire)

    assert {:error, :acp_unexpected_response} =
             Wire.feed(wire, frame(%{"id" => 1, "result" => %{}}))
  end

  test "rejects malformed and ambiguous messages and bounds a never-ending line" do
    for bytes <- [
          "diagnostic text\n",
          "[]\n",
          "{}\n",
          frame(%{"id" => nil, "method" => "x"}),
          frame(%{"id" => 1, "method" => "x", "result" => %{}}),
          frame(%{"id" => 1, "result" => %{}, "error" => %{"code" => 1}}),
          frame(%{"id" => 1, "method" => "x", "params" => []}),
          frame(%{"id" => 1, "result" => "not an ACP response"})
        ] do
      assert {:error, :acp_invalid_message} = Wire.feed(%Wire{}, bytes)
    end

    assert {:ok, wire, []} = Wire.feed(%Wire{}, String.duplicate("x", 1_048_576))
    assert {:error, :acp_frame_too_large} = Wire.feed(wire, "x")
    assert {:error, :acp_unexpected_eof} = Wire.finish(wire)
  end

  test "bounds outstanding requests and removes provider error detail" do
    wire =
      Enum.reduce(1..8, %Wire{}, fn _, wire ->
        {:ok, wire, _, _} = Wire.request(wire, "initialize", %{})
        wire
      end)

    assert {:error, :acp_pending_limit} = Wire.request(wire, "initialize", %{})
    assert {:error, :acp_unexpected_eof} = Wire.finish(wire)

    assert {:ok, _, [{:response, 1, "initialize", {:error, -32_000}}]} =
             Wire.feed(
               wire,
               frame(%{
                 "id" => 1,
                 "error" => %{
                   "code" => -32_000,
                   "message" => "secret-canary",
                   "data" => %{"private" => "hidden"}
                 }
               })
             )
  end

  test "preserves request IDs while rejecting unknown client capabilities" do
    assert {:ok, _, [{:request, "permission-1", "session/request_permission", %{}}]} =
             Wire.feed(
               %Wire{},
               frame(%{"id" => "permission-1", "method" => "session/request_permission"})
             )

    assert {:ok, bytes} = Wire.reject("permission-1")
    assert %{"id" => "permission-1", "error" => %{"code" => -32_601}} = Jason.decode!(bytes)
    assert {:ok, bytes} = Wire.reply(0, %{"outcome" => %{"outcome" => "cancelled"}})
    assert Jason.decode!(bytes)["id"] == 0
  end

  defp frame(message), do: Jason.encode!(Map.put(message, "jsonrpc", "2.0")) <> "\n"
end
