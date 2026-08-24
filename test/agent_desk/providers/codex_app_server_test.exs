defmodule AgentDesk.Providers.Codex.AppServerTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.Codex.AppServer

  test "decodes nested thread ids without a jsonrpc header and includes them on turns" do
    state = AppServer.init_decode()
    {:ok, init, state} = AppServer.encode(:initialize, state)
    {:ok, initialized, state} = AppServer.encode(:initialized, state)
    {:ok, start, state} = AppServer.encode({:start_session, "/tmp/work"}, state)

    refute init =~ "jsonrpc"
    refute initialized =~ "jsonrpc"
    assert start =~ "/tmp/work"

    {:ok, [initialize_result], state} =
      AppServer.decode_line(~s({"id":1,"result":{"userAgent":"codex"}}), state)

    assert initialize_result.type == :initialize_result

    {:ok, [ready], state} =
      AppServer.decode_line(~s({"id":2,"result":{"thread":{"id":"thr_1"}}}), state)

    assert ready.type == :session_ready
    assert ready.payload["provider_session_id"] == "thr_1"

    {:ok, [], state} =
      AppServer.decode_line(
        ~s({"method":"thread/started","params":{"thread":{"id":"thr_1"}}}),
        state
      )

    {:ok, prompt, state} = AppServer.encode({:prompt, "hello"}, state)
    assert prompt =~ "thr_1"
    assert prompt =~ "hello"

    png = Path.join(System.tmp_dir!(), "cuckoding-#{System.unique_integer([:positive])}.png")
    File.write!(png, "not-a-real-png")

    {:ok, with_image, _state} =
      AppServer.encode(
        {:prompt, "see", [%{"name" => "shot.png", "path" => png, "mime" => "image/png"}]},
        state
      )

    encoded = IO.iodata_to_binary(with_image)
    assert encoded =~ "localImage" or encoded =~ "data:image/png"
    assert encoded =~ "see"
    File.rm(png)

    {:ok, "", _state} = AppServer.encode({:configure_mcp, "/tmp/mcp.json"}, state)
  end

  test "still understands the fixture threadId result shape" do
    state = AppServer.init_decode()
    {:ok, _, state} = AppServer.encode(:initialize, state)
    {:ok, _, state} = AppServer.encode({:start_session, "/tmp"}, state)

    {:ok, _, state} =
      AppServer.decode_line(
        ~s({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"fixture"}}),
        state
      )

    {:ok, [ready], _state} =
      AppServer.decode_line(
        ~s({"jsonrpc":"2.0","id":2,"result":{"threadId":"thread-fixture-1"}}),
        state
      )

    assert ready.payload["provider_session_id"] == "thread-fixture-1"
  end
end
