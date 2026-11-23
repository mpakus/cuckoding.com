defmodule BossWeb.LayoutsTest do
  use BossWeb.ConnCase, async: false

  setup %{conn: conn} do
    {:ok, conn: %{conn | host: "127.0.0.1", port: 4002}}
  end

  test "the application shell exposes a keyboard skip target and omits the marketing motion toggle",
       %{conn: conn} do
    response = get(conn, "/")
    html = html_response(response, 200)

    assert html =~ ~s(href="#main-content")
    assert html =~ ~s(id="main-content" class="app-main" tabindex="-1")
    assert html =~ ~s(name="csrf-token")
    assert get_resp_header(response, "referrer-policy") == ["same-origin"]
    assert html =~ ~s(data-motion="off")
    refute html =~ "Pause motion"
    refute html =~ "app-motion-toggle"
    refute html =~ "app-motion-control"
  end

  test "the shared navigation names the current application section", %{conn: conn} do
    projects = html_response(get(conn, "/"), 200)
    assert projects =~ ~s(href="/" aria-current="page">Projects)
    refute projects =~ ~s(href="/agents" aria-current="page")

    agents = html_response(get(conn, "/agents"), 200)
    assert agents =~ ~s(href="/agents" aria-current="page">Agents)
    refute agents =~ ~s(href="/" aria-current="page")
  end
end
