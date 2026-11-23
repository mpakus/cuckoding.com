defmodule BossWeb.LocalAccessTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    {:ok, conn: %{conn | host: "127.0.0.1", port: 4002}}
  end

  test "loopback opens directly without a token prompt and /unlock is removed", %{conn: conn} do
    response = get(conn, "/")
    html = html_response(response, 200)
    assert html =~ "Projects"
    refute html =~ "Connect this browser"
    refute html =~ "One-use token"

    cookie = response.resp_cookies["_boss_key"]
    assert cookie.http_only
    assert cookie.same_site == "Strict"
    assert get_resp_header(response, "referrer-policy") == ["same-origin"]

    assert conn |> get("/unlock") |> response(404)
    assert {:ok, view, live_html} = live(conn, "/")
    assert live_html =~ "Projects"
    assert render(view) =~ "Closing this tab"
  end

  test "localhost host on the configured port is accepted", %{conn: conn} do
    localhost = %{conn | host: "localhost", port: 4002}
    assert html_response(get(localhost, "/"), 200) =~ "Projects"

    same_origin = put_req_header(localhost, "origin", "http://localhost:4002")
    assert html_response(get(same_origin, "/agents"), 200) =~ "Agents"
  end

  test "foreign and null origins, wrong port and rebinding hosts are rejected", %{conn: conn} do
    for origin <- ["https://evil.example", "null", "http://127.0.0.1:4444"] do
      assert conn |> put_req_header("origin", origin) |> get("/") |> response(403) ==
               "Forbidden"

      assert conn |> put_req_header("origin", origin) |> get("/agents") |> response(403) ==
               "Forbidden"
    end

    assert %{conn | host: "evil.example"} |> get("/") |> response(403) == "Forbidden"
    assert %{conn | port: 4444} |> get("/") |> response(403) == "Forbidden"
  end

  @tag capture_log: true
  test "WebSocket configuration rejects foreign origins", %{conn: conn} do
    config = BossWeb.Endpoint.config(:check_origin)
    assert config == ["http://127.0.0.1:4002", "http://localhost:4002"]
    foreign = conn |> put_req_header("origin", "https://evil.example")

    checked =
      Phoenix.Socket.Transport.check_origin(
        foreign,
        Phoenix.LiveView.Socket,
        BossWeb.Endpoint,
        []
      )

    assert checked.halted
    assert checked.status == 403
  end
end
