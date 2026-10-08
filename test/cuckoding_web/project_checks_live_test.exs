defmodule CuckodingWeb.ProjectChecksLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Cuckoding.{BrowserToken, Foundation, ProjectChecks, Repo}

  defp editor(conn) do
    arena = Cuckoding.DataCase.arena_fixture()
    signed = sign_in(conn)
    path = "/arenas/#{arena.id}/checks"
    {:ok, view, _} = live(signed, path)
    view |> element("button", "Add check") |> render_click()

    fields = %{
      "name" => "Tests",
      "executable" => "mix",
      "argument_lines" => "test\n--only\na b",
      "directory" => ".",
      "timeout_seconds" => "300"
    }

    {arena, signed, path, view, fields}
  end

  test "preview, explicit consent, literal arguments and saved history survive reconnect", %{
    conn: conn
  } do
    {arena, signed, path, view, fields} = editor(conn)
    {:ok, arena_view, _} = live(signed, "/arenas/#{arena.id}")
    assert has_element?(arena_view, "a[href='#{path}']", "Project checks")
    view |> form("#checks-form", checks: %{"0" => fields}) |> render_submit()
    assert has_element?(view, "#checks-preview pre", ~s(["mix","test","--only","a b"]))
    view |> form("#checks-confirm") |> render_submit()
    assert has_element?(view, "#checks-error", "confirm before saving")
    Foundation.broadcast()
    assert has_element?(view, "#checks-error")
    view |> form("#checks-confirm", confirmed: "true") |> render_submit()
    assert ProjectChecks.current(arena.id).revision == 1
    assert has_element?(view, "[role=status]", "Nothing was run")
    assert has_element?(view, "#checks-history[phx-mounted*=ignore_attrs]")
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#checks-revision-1", "a b")
    assert has_element?(again, "input[value='Tests']")
    again |> element("button", "Remove from draft") |> render_click()
    again |> form("#checks-form") |> render_submit()
    assert has_element?(again, "#checks-preview", "No checks declared")
    assert ProjectChecks.current(arena.id).revision == 1
    again |> form("#checks-confirm", confirmed: "true") |> render_submit()
    assert ProjectChecks.current(arena.id).revision == 2
    assert length(ProjectChecks.history(arena.id)) == 2
  end

  test "edits clear preview and consent, stale updates retain text and reload asks before discard",
       %{conn: conn} do
    {arena, _, _, view, fields} = editor(conn)
    view |> form("#checks-form", checks: %{"0" => fields}) |> render_submit()
    view |> form("#checks-confirm", confirmed: "true") |> render_change()

    view
    |> form("#checks-form",
      checks: %{"0" => %{fields | "name" => "Keep <script>literal</script>"}}
    )
    |> render_change()

    refute has_element?(view, "#checks-confirm")
    view |> form("#checks-form") |> render_submit()
    refute has_element?(view, "#checks-preview script")
    view |> form("#checks-confirm", confirmed: "true") |> render_change()

    other = %{
      "id" => Ecto.UUID.generate(),
      "name" => "Saved elsewhere",
      "executable" => "cargo",
      "arguments" => ["test"],
      "directory" => ".",
      "timeout_seconds" => 120
    }

    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), arena.id, 0, [other], true)
    assert has_element?(view, "input[value='Keep <script>literal</script>']")
    refute has_element?(view, "#checks-confirm input[checked]")
    view |> form("#checks-confirm") |> render_submit(%{"confirmed" => "true"})
    assert ProjectChecks.current(arena.id).revision == 1
    view |> element("button", "Reload saved checks") |> render_click()
    assert has_element?(view, "button", "Keep editing")
    view |> element("button", "Keep editing") |> render_click()
    assert has_element?(view, "input[value='Keep <script>literal</script>']")
    view |> element("button", "Reload saved checks") |> render_click()
    view |> element("button", "Discard draft and reload") |> render_click()
    assert has_element?(view, "input[value='Saved elsewhere']")
  end

  test "recovered foreign/stale forms cannot preview or save and expired sessions cannot mutate",
       %{conn: conn} do
    {arena, _, _, view, fields} = editor(conn)

    view
    |> form("#checks-form", checks: %{"0" => fields})
    |> render_change(%{"arena_id" => Ecto.UUID.generate()})

    assert has_element?(view, "input[value='Tests']")
    view |> form("#checks-form") |> render_submit(%{"base_revision" => "99"})
    assert has_element?(view, "#checks-error", "draft is kept")
    refute has_element?(view, "#checks-confirm")
    view |> form("#checks-form") |> render_submit()
    refute has_element?(view, "#checks-confirm")
    view |> element("button", "Reload saved checks") |> render_click()
    view |> element("button", "Discard draft and reload") |> render_click()
    view |> element("button", "Add check") |> render_click()
    view |> form("#checks-form", checks: %{"0" => fields}) |> render_submit()
    view |> form("#checks-confirm", confirmed: "true") |> render_submit(%{"digest" => "forged"})
    assert ProjectChecks.current(arena.id).revision == 0
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> form("#checks-confirm", confirmed: "true") |> render_submit()
    assert_redirect(view, "/locked")
    assert ProjectChecks.current(arena.id).revision == 0
  end
end
