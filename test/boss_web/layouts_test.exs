defmodule BossWeb.LayoutsTest do
  use BossWeb.ConnCase, async: false

  setup %{conn: conn} do
    {:ok, conn: %{conn | host: "127.0.0.1", port: 4002}}
  end

  test "the public shell preserves access and exposes a keyboard skip target", %{conn: conn} do
    response = get(conn, "/unlock")
    html = html_response(response, 200)

    assert html =~ ~s(href="#main-content")
    assert html =~ ~s(id="main-content" class="app-main" tabindex="-1")
    assert html =~ ~s(name="csrf-token")
    assert html =~ ~s(name="_csrf_token")
    assert get_resp_header(response, "referrer-policy") == ["same-origin"]
    assert html =~ ~s(data-motion="off")
    assert html =~ ~s(id="app-motion-control" class="app-motion-label" hidden)
    assert html =~ ~s(id="app-motion-toggle" type="checkbox" disabled)
  end

  test "the shared navigation names the current application section", %{conn: conn} do
    {:ok, session} = Boss.LocalAccess.exchange(Boss.LocalAccess.new_token())
    conn = init_test_session(conn, local_session: session)

    projects = html_response(get(conn, "/"), 200)
    assert projects =~ ~s(href="/" aria-current="page">Projects)
    refute projects =~ ~s(href="/agents" aria-current="page")

    agents = html_response(get(conn, "/agents"), 200)
    assert agents =~ ~s(href="/agents" aria-current="page">Agents)
    refute agents =~ ~s(href="/" aria-current="page")
  end
end
