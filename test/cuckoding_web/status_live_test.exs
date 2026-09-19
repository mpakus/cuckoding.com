defmodule CuckodingWeb.StatusLiveTest do
  use CuckodingWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cuckoding.Projects

  test "renders the project-first dashboard and resource status", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Your Cuckoding workspace"
    assert has_element?(view, "main#main-content")
    assert has_element?(view, "h1", "Your Cuckoding workspace")
    assert has_element?(view, "#overview-heading", "Application and resources")
    assert has_element?(view, "#active-agent-count", "0")
    assert has_element?(view, "#projects-heading", "Projects")
    assert has_element?(view, "#projects-empty", "Nothing runs during project setup")
    assert has_element?(view, "a[href='/projects/new']", "Add project")
    refute has_element?(view, "#guided-run-form")
    refute html =~ "Create queued run"
    assert has_element?(view, "nav[aria-label=Diagnostics] a[href='/health']", "Health JSON")
  end

  test "lists a previously registered project and its next action", %{conn: conn} do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Existing project #{suffix}",
        repo_path: "/tmp/existing-project-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/existing-workspaces-#{suffix}",
        port_range_start: 47_000,
        port_range_end: 47_100
      })

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#project-#{project.id}", project.name)
    assert has_element?(view, "#project-#{project.id}", "main")
    assert has_element?(view, "#project-#{project.id}", "Ready for board setup")
  end

  test "sets a restrictive content security policy", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "default-src 'self'"
    assert policy =~ "frame-ancestors 'none'"
    refute policy =~ "unsafe-inline"
  end
end
