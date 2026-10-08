defmodule CuckodingWeb.SpecificationLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  import Cuckoding.SpecificationFixtures
  alias Cuckoding.{BrowserToken, Foundation, Repo, Specifications, Tabulae}
  setup do: specification_fixture()

  test "preview, consent, accepted revision and reconnect preserve unsaved editor text", %{
    conn: conn,
    board: b,
    task: task
  } do
    signed = sign_in(conn)
    path = "/arenas/#{b.arena_id}/tabulae/#{b.id}"
    {:ok, view, _} = live(signed, path)
    view |> element("button[aria-label='Edit Health endpoint']") |> render_click()
    assert has_element?(view, "#task-specifications[phx-mounted*=ignore_attrs]")
    view |> form("#draft-form", description: "Unsaved text") |> render_change()
    assert has_element?(view, "#task-specifications button[disabled]", "Preview specification")
    view |> form("#draft-form", description: "Return a local status.") |> render_change()
    view |> element("#task-specifications button", "Preview specification") |> render_click()
    assert has_element?(view, "#spec-preview pre", "Source draft revision: 1")
    view |> form("#spec-accept-form") |> render_submit()
    assert has_element?(view, "#spec-error", "confirm acceptance")
    view |> form("#spec-accept-form", confirmed: "true") |> render_submit()
    [command] = Specifications.history(b.id, task)
    assert has_element?(view, "#task-specifications button", "Cancel acceptance")
    {:ok, claim} = Foundation.claim()
    view |> form("#draft-form", title: "Keep my unsaved title") |> render_change()
    {:ok, _} = Foundation.finish(claim, Specifications.execute(claim))
    assert has_element?(view, "#column-todo #task-#{task}")
    assert has_element?(view, "#draft-title-input[value='Keep my unsaved title']")
    assert has_element?(view, "#spec-#{command.id}", "revisions are current")

    assert has_element?(
             view,
             "#spec-#{command.id} a[href='/specifications/#{command.id}/download']"
           )

    view |> element("#spec-#{command.id} button", "Reload task") |> render_click()
    assert has_element?(view, "button", "Keep editing")
    view |> element("button", "Keep editing") |> render_click()
    assert has_element?(view, "#draft-title-input[value='Keep my unsaved title']")
    {:ok, again, _} = live(signed, path)
    again |> element("button[aria-label='Edit Health endpoint']") |> render_click()
    assert has_element?(again, "#draft-title", "revision 2")
    assert has_element?(again, "#spec-#{command.id}", "revisions are current")
    again |> form("#draft-form", title: "Changed specification") |> render_submit()
    again |> element("button[aria-label='Edit Changed specification']") |> render_click()
    assert has_element?(again, "#spec-#{command.id}", "Historical specification")
  end

  test "live changes clear consent, sources render literally and expired sessions cannot accept",
       %{conn: conn, board: b, task: task, attrs: attrs} do
    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        b.arena_id,
        b.id,
        task,
        1,
        Map.put(attrs, "description", "<script>canary</script>")
      )

    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{b.arena_id}/tabulae/#{b.id}")
    view |> element("button[aria-label='Edit Health endpoint']") |> render_click()
    view |> element("#task-specifications button", "Preview specification") |> render_click()
    assert has_element?(view, "#spec-preview pre", "<script>canary</script>")
    refute has_element?(view, "#spec-preview script")
    view |> form("#spec-accept-form", confirmed: "true") |> render_change()
    assert has_element?(view, "#spec-accept-form input[checked]")
    {:ok, _} = Tabulae.save(Ecto.UUID.generate(), b.arena_id, b.id, task, 2, attrs)
    refute has_element?(view, "#spec-accept-form input[checked]")
    assert has_element?(view, "#spec-preview", "no longer current")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> form("#spec-accept-form") |> render_submit(%{"confirmed" => "true"})
    assert_redirect(view, "/locked")
    assert Specifications.history(b.id, task) == []
  end

  test "downloads require a live session, completed spec ID and matching private file", %{
    conn: conn,
    board: b,
    task: task,
    root: root
  } do
    {:ok, command} = request_spec(b, task)
    path = "/specifications/#{command.id}/download"
    assert conn |> get(path) |> response(401)
    assert conn |> sign_in() |> get(path) |> response(410)
    {:ok, claim} = Foundation.claim()
    {:ok, _} = Foundation.finish(claim, Specifications.execute(claim))
    response_conn = conn |> sign_in() |> get(path)
    assert response(response_conn, 200) == command.payload["markdown"]

    assert get_resp_header(response_conn, "content-disposition") == [
             "attachment; filename=\"specification-#{command.id}.md\""
           ]

    assert get_resp_header(response_conn, "x-content-type-options") == ["nosniff"]
    assert conn |> sign_in() |> get("/specifications/#{b.command_id}/download") |> response(410)
    File.write!(Path.join(root, "specifications/#{command.id}.md"), "tampered")
    assert conn |> sign_in() |> get(path) |> response(410)
    signed = sign_in(conn)
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    assert signed |> get(path) |> response(401)
  end
end
