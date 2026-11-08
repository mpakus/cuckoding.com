defmodule BossWeb.LocalAccessTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    {:ok, conn: %{conn | host: "127.0.0.1", port: 4002}, token: Boss.LocalAccess.new_token()}
  end

  test "anonymous visitors must unlock; the form never reflects a query token", %{conn: conn} do
    assert redirected_to(get(conn, "/")) == "/unlock"
    html = conn |> get("/unlock?token=do-not-reflect-me") |> html_response(200)
    assert html =~ "One-use token"
    assert html =~ "Remember this browser for 30 days"
    refute html =~ "do-not-reflect-me"
  end

  test "bootstrap requires CSRF", %{conn: conn, token: token} do
    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      conn
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/unlock", token: token, remember: "true")
    end
  end

  test "one-use token creates a session that survives reopening the LiveView", %{
    conn: conn,
    token: token
  } do
    {conn, csrf} = unlock_form(conn)
    signed_in = conn |> post("/unlock", token: token, _csrf_token: csrf)
    assert redirected_to(signed_in) == "/"
    cookie = signed_in.resp_cookies["_boss_key"]
    assert cookie.http_only
    assert cookie.same_site == "Strict"
    refute Map.has_key?(signed_in.resp_cookies, "_boss_remember_4002")
    assert {:ok, view, html} = live(local_recycle(signed_in), "/")
    assert html =~ "Projects"
    assert render(view) =~ "Closing this tab"
    assert {:ok, _view, _html} = live(local_recycle(signed_in), "/")

    {fresh, csrf} = unlock_form(%{build_conn() | host: "127.0.0.1", port: 4002})

    assert fresh |> post("/unlock", token: token, _csrf_token: csrf) |> html_response(401) =~
             "Token is invalid, expired or already used"
  end

  test "only a valid remembered cookie reconnects after the session service restarts", %{
    conn: conn,
    token: token
  } do
    on_exit(fn -> :ok = Boss.LocalAccess.forget_browser() end)
    {form, csrf} = unlock_form(conn)
    remembered = post(form, "/unlock", token: token, _csrf_token: csrf, remember: "true")
    assert redirected_to(remembered) == "/"

    cookie_name = "_boss_remember_4002"
    cookie = remembered.resp_cookies[cookie_name]
    assert cookie.path == "/unlock"
    assert cookie.http_only
    assert cookie.same_site == "Strict"
    assert cookie.max_age == 30 * 24 * 60 * 60

    {form, csrf} = unlock_form(conn)
    ordinary = post(form, "/unlock", token: Boss.LocalAccess.new_token(), _csrf_token: csrf)
    assert redirected_to(ordinary) == "/"

    assert :ok = Supervisor.terminate_child(Boss.Supervisor, Boss.LocalAccess)
    assert {:ok, _pid} = Supervisor.restart_child(Boss.Supervisor, Boss.LocalAccess)

    assert redirected_to(get(local_recycle(ordinary), "/")) == "/unlock"
    assert html_response(get(local_recycle(ordinary), "/unlock"), 200) =~ "One-use token"
    assert redirected_to(get(local_recycle(remembered), "/")) == "/unlock"

    assert conn
           |> put_req_cookie(cookie_name, String.duplicate("x", 43))
           |> get("/unlock")
           |> html_response(200) =~ "One-use token"

    assert local_recycle(remembered)
           |> put_req_header("origin", "https://evil.example")
           |> get("/unlock")
           |> response(403) == "Forbidden"

    restored = get(local_recycle(remembered), "/unlock")
    assert redirected_to(restored) == "/"
    refute Map.has_key?(restored.resp_cookies, cookie_name)
    assert {:ok, _view, html} = live(local_recycle(restored), "/")
    assert html =~ "Projects"

    assert :ok = Boss.LocalAccess.forget_browser()
    assert html_response(get(local_recycle(remembered), "/unlock"), 200) =~ "One-use token"
  end

  test "foreign origin cannot consume a valid token", %{conn: conn, token: token} do
    {conn, csrf} = unlock_form(conn)
    foreign = conn |> put_req_header("origin", "https://evil.example")

    assert foreign |> post("/unlock", token: token, _csrf_token: csrf) |> response(403) ==
             "Forbidden"

    assert conn |> post("/unlock", token: token, _csrf_token: csrf) |> redirected_to() == "/"
  end

  test "foreign and null origins, wrong port and rebinding hosts are rejected", %{conn: conn} do
    for origin <- ["https://evil.example", "null", "http://127.0.0.1:4444"] do
      assert conn |> put_req_header("origin", origin) |> get("/unlock") |> response(403) ==
               "Forbidden"
    end

    assert %{conn | host: "evil.example"} |> get("/unlock") |> response(403) == "Forbidden"
  end

  test "LiveView logs do not expose its session grant", %{conn: conn, token: token} do
    {:ok, session} = Boss.LocalAccess.exchange(token)
    conn = init_test_session(conn, local_session: session)
    previous_level = Logger.level()
    Logger.configure(level: :debug)

    try do
      logs = ExUnit.CaptureLog.capture_log(fn -> assert {:ok, _, _} = live(conn, "/") end)
      refute logs =~ session
    after
      Logger.configure(level: previous_level)
    end
  end

  test "LiveView mount rechecks the signed session" do
    assert {:halt, socket} =
             BossWeb.LocalSession.on_mount(:default, %{}, %{}, %Phoenix.LiveView.Socket{})

    assert socket.redirected == {:redirect, %{to: "/unlock", status: 302}}
  end

  @tag capture_log: true
  test "socket configuration rejects foreign origins", %{conn: conn} do
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

  defp local_recycle(conn), do: %{recycle(conn) | port: 4002}

  defp unlock_form(conn) do
    response = get(conn, "/unlock")
    html = html_response(response, 200)
    [_, csrf] = Regex.run(~r/name="_csrf_token"[^>]*value="([^"]+)"/, html)
    {response |> local_recycle() |> put_private(:plug_skip_csrf_protection, false), csrf}
  end
end
