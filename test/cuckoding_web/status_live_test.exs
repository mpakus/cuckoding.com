defmodule CuckodingWeb.StatusLiveTest do
  use CuckodingWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders accessible application and dependency status", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Cuckoding is ready"
    assert has_element?(view, "main#main-content")
    assert has_element?(view, "h1", "Cuckoding is ready")
    assert has_element?(view, "[role=status]", "Application status: Operational")
    assert has_element?(view, "nav[aria-label=Diagnostics] a[href='/health']", "Health JSON")
    assert has_element?(view, "fieldset legend", "Experimental runtimes")
    assert has_element?(view, "input[name=runtime][value=cursor_agent][disabled]")
    assert has_element?(view, "#runtime-cursor_agent-warning", "user-global MCP process")
    assert has_element?(view, "input[name=runtime][value=opencode][disabled]")
    assert has_element?(view, "#runtime-opencode-warning", "no supported OpenCode CLI")
  end

  test "sets a restrictive content security policy", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "default-src 'self'"
    assert policy =~ "frame-ancestors 'none'"
    refute policy =~ "unsafe-inline"
  end
end
