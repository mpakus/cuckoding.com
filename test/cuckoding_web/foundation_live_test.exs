defmodule CuckodingWeb.FoundationLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Cuckoding.{BrowserToken, Foundation, Repo, ShellAuth}

  test "foreign hosts, origins, ports and shell callers are rejected", %{conn: conn} do
    assert conn |> Map.put(:host, "evil.test") |> get("/") |> response(403)
    assert conn |> Map.put(:port, 9000) |> get("/") |> response(403)
    assert conn |> put_req_header("origin", "https://evil.test") |> get("/") |> response(403)
    assert conn |> put_req_header("origin", "null") |> get("/") |> response(403)
    assert conn |> put_req_header("sec-fetch-site", "cross-site") |> get("/") |> response(403)
    assert conn |> post("/shell/open") |> response(401)
    refute CuckodingWeb.Boundary.allowed_origin?(URI.parse("http://127.0.0.1:9000"))
    assert CuckodingWeb.Boundary.allowed_origin?(URI.parse("http://127.0.0.1:4002"))
  end

  test "browser handoff is single-use and cannot redirect off-host", %{conn: conn} do
    handoff = ShellAuth.handoff()
    opened = get(conn, "/open", token: handoff, view: "https://evil.test")
    assert redirected_to(opened) == "/"
    assert get_resp_header(opened, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(opened, "cache-control") == ["no-store"]
    assert get(conn, "/open", token: handoff) |> response(401)
    assert get(conn, "/open") |> response(401)
    assert get_session(opened, :session_id)
  end

  test "unauthenticated users cannot mount; setup persists through reconnect", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/locked"}}} = live(conn, "/")
    signed = sign_in(conn)
    assert {:ok, view, html} = live(signed, "/settings")
    assert html =~ "Your starting lineup."
    assert html =~ "Not checked"
    view |> element("button", "Check setup") |> render_click()
    assert Foundation.pending?()
    {:ok, claim} = Foundation.claim()

    {:ok, _} =
      Foundation.finish(claim, %{"rtk" => %{"status" => "found", "path" => "/test/bin/rtk"}})

    assert render(view) =~ "/test/bin/rtk"
    assert has_element?(view, "#tool-location-rtk[phx-mounted*=ignore_attrs]")
    assert {:ok, _, html} = live(signed, "/settings")
    assert html =~ "Found"
    assert html =~ "/test/bin/rtk"
  end

  test "expired browser authority cannot mutate even on an existing live connection", %{
    conn: conn
  } do
    {:ok, view, _} = conn |> sign_in() |> live("/settings")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("button", "Check setup") |> render_click()
    assert_redirect(view, "/locked")
    refute Foundation.pending?()
  end

  test "public pages expose keyboard navigation and honest empty state", %{conn: conn} do
    {:ok, view, html} = conn |> sign_in() |> live("/")
    assert has_element?(view, "a[href='#main']", "Skip to content")
    assert html =~ "Foundation preview"
    assert has_element?(view, "a[href='/settings']", "Check your setup")
    refute html =~ "Start battle"
  end

  test "expired authority cannot receive live workspace updates", %{conn: conn} do
    {:ok, view, _} = conn |> sign_in() |> live("/settings")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    Foundation.broadcast()
    assert_redirect(view, "/locked")
  end

  test "Codex requires explicit consent and preserves entered paths through updates", %{
    conn: conn
  } do
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/settings")
    assert has_element?(view, "label[for='codex-path']", "Codex executable")
    assert has_element?(view, "input[name='confirmed'][required]")
    view |> form("#codex-check", path: "/bin/sh") |> render_change()
    Foundation.broadcast()
    assert has_element?(view, "#codex-path[value='/bin/sh']")
    view |> form("#codex-check", path: "/bin/sh", confirmed: "true") |> render_change()
    assert has_element?(view, "input[name='confirmed'][checked]")
    view |> form("#codex-check", path: "/bin/ls", confirmed: "true") |> render_change()
    refute has_element?(view, "input[name='confirmed'][checked]")
    view |> form("#codex-check", path: "/bin/sh") |> render_submit()
    assert render(view) =~ "Confirm that you trust this executable"
    refute Foundation.pending_probe()
    view |> form("#codex-check", path: "/bin/sh", confirmed: "true") |> render_submit()
    assert Foundation.pending_probe()
    assert has_element?(view, "button", "Cancel check")
    view |> element("button", "Cancel check") |> render_click()
    assert render(view) =~ "Check cancelled."
    assert {:ok, _, html} = live(signed, "/settings")
    assert html =~ "Check cancelled."
  end
end
