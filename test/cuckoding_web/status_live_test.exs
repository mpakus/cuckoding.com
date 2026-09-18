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
    assert has_element?(view, "#guided-run-form input[name='guided_run[repo_path]']")
    assert has_element?(view, "#guided-run-form select[name='guided_run[runtime]']")
    assert has_element?(view, "#guided-run-form input[name='guided_run[confirmed]'][required]")
    assert has_element?(view, "#host-runner-notice", "not a sandbox")
  end

  test "guided setup requires an explicit trusted-host confirmation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#guided-run-form",
      guided_run: %{
        name: "Example",
        repo_path: "/tmp/example",
        default_branch: "main",
        runtime: "codex",
        executable_path: "/usr/bin/true",
        task_title: "Example task"
      }
    )
    |> render_submit()

    assert has_element?(
             view,
             "#guided-run-error[role=alert]",
             "Confirm the trusted-host and worktree changes"
           )
  end

  test "sets a restrictive content security policy", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "default-src 'self'"
    assert policy =~ "frame-ancestors 'none'"
    refute policy =~ "unsafe-inline"
  end
end
