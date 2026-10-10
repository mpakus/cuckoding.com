defmodule CuckodingWeb.BattlePreviewLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  import Cuckoding.SpecificationFixtures
  alias Cuckoding.{BrowserToken, Command, Event, Foundation, Repo, Tabulae}

  setup do: specification_fixture()

  test "read-only preview is linked, escaped and marked stale without replacing disclosures",
       ctx do
    %{conn: conn, board: b, task: task, attrs: attrs} = ctx
    signed = sign_in(conn)
    path = "/arenas/#{b.arena_id}/tabulae/#{b.id}/battle"
    {:ok, board, _} = live(signed, "/arenas/#{b.arena_id}/tabulae/#{b.id}")
    assert has_element?(board, "a[href='#{path}']", "Battle preview")
    before = {Repo.all(Command), Repo.all(Event)}
    {:ok, view, _} = live(signed, path)
    assert has_element?(view, "#execution-unavailable", "not available")
    refute has_element?(view, "#refresh-preview[phx-disable-with]")
    assert has_element?(view, "#preview-checks", "No checks declared")
    assert has_element?(view, "#preview-team[phx-mounted*=ignore_attrs]")
    assert has_element?(view, "#preview-team a[href='/agents']", "Agents")
    assert has_element?(view, "#preview-tasks[phx-mounted*=ignore_attrs]")
    assert {Repo.all(Command), Repo.all(Event)} == before
    refute has_element?(view, "button", "Start battle")

    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        b.arena_id,
        b.id,
        task,
        1,
        Map.put(attrs, "title", "<script>updated</script>")
      )

    assert has_element?(view, "#preview-stale", "Saved state changed")
    assert has_element?(view, "#preview-tasks h3", attrs["title"])

    view
    |> element("button", "Refresh preview")
    |> render_click(%{"arena_id" => Ecto.UUID.generate()})

    refute has_element?(view, "#preview-stale")
    assert has_element?(view, "#preview-tasks h3", "<script>updated</script>")
    refute has_element?(view, "#preview-tasks script")
    generation = :sys.get_state(view.pid).socket.assigns.generation
    send(view.pid, {:preview_expired, make_ref()})
    refute has_element?(view, "#preview-stale")
    send(view.pid, {:preview_expired, generation})
    assert has_element?(view, "#preview-stale", "over a minute old")
    view |> element("button", "Refresh preview") |> render_click()
    send(view.pid, {:preview_expired, generation})
    refute has_element?(view, "#preview-stale")
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#preview-tasks h3", "<script>updated</script>")
    assert has_element?(again, "#preview-checks", "revision 0")
  end

  test "scope and expired browser sessions cannot inspect or refresh", %{conn: conn, board: b} do
    path = "/arenas/#{b.arena_id}/tabulae/#{b.id}/battle"
    assert {:error, {:redirect, %{to: "/locked"}}} = live(conn, path)
    signed = sign_in(conn)
    other = Cuckoding.DataCase.arena_fixture()

    assert {:error, {:redirect, %{to: "/arenas"}}} =
             live(signed, "/arenas/#{other.id}/tabulae/#{b.id}/battle")

    {:ok, view, _} = live(signed, path)
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("button", "Refresh preview") |> render_click()
    assert_redirect(view, "/locked")
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, path)
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    Foundation.broadcast()
    assert_redirect(view, "/locked")
  end
end
