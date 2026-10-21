defmodule CuckodingWeb.TransportTest do
  use CuckodingWeb.ConnCase
  @moduletag capture_log: true

  setup do
    server =
      start_supervised!(
        {Bandit, plug: CuckodingWeb.Endpoint, ip: {127, 0, 0, 1}, port: 0, startup_log: false}
      )

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(server)
    %{wire_port: port}
  end

  test "real HTTP transport rejects malformed authority before dispatch and retains local host/origin gates",
       %{wire_port: port} do
    # The test endpoint has server: false, so its configured logical port stays 4002.
    authority = "127.0.0.1:#{CuckodingWeb.Boundary.port()}"
    assert status(port, "GET / HTTP/1.1\r\nHost: #{authority}\r\n") == 302
    assert status(port, "GET http://#{authority}/ HTTP/1.1\r\nHost: #{authority}\r\n") == 302

    assert status(port, "GET http://foreign.invalid:4002/ HTTP/1.1\r\nHost: #{authority}\r\n") ==
             403

    assert status(
             port,
             "GET / HTTP/1.1\r\nHost: #{authority}\r\nOrigin: https://foreign.invalid\r\n"
           ) == 403

    for host <- ["good.example@evil.example", "ex#am.com", "bad\0host"] do
      assert status(port, "GET http://#{host}:4002/ HTTP/1.1\r\nHost: #{authority}\r\n") == 400
    end
  end

  test "Phoenix parser errors render through the upgraded adapter and leave the listener usable",
       %{wire_port: port} do
    host = "Host: 127.0.0.1:#{CuckodingWeb.Boundary.port()}\r\n"

    assert status(
             port,
             "POST /shell/status HTTP/1.1\r\n" <>
               host <>
               "Content-Type: application/json\r\nContent-Length: 4\r\n",
             "{bad"
           ) == 400

    assert status(
             port,
             "POST /shell/status HTTP/1.1\r\n" <>
               host <>
               "Content-Type: application/json\r\nContent-Length: 2\r\n",
             "{}"
           ) == 401

    assert status(port, "GET / HTTP/1.1\r\n" <> host) == 302
  end

  defp status(port, headers, body \\ "") do
    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, packet: :line], 2_000)

    try do
      :ok = :gen_tcp.send(socket, headers <> "Connection: close\r\n\r\n" <> body)
      {:ok, response} = :gen_tcp.recv(socket, 0, 2_000)
      [_, status | _] = String.split(response, " ", parts: 3)
      String.to_integer(status)
    after
      :gen_tcp.close(socket)
    end
  end
end
