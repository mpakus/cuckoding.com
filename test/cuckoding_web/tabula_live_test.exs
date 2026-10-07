defmodule CuckodingWeb.TabulaLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Cuckoding.{BrowserToken, Foundation, Repo, Tabulae}

  setup do
    arena = Cuckoding.DataCase.arena_fixture()
    {:ok, board} = Tabulae.create(Ecto.UUID.generate(), arena.id, "First battle")
    %{arena: arena, board: board, path: "/arenas/#{arena.id}/tabulae/#{board.id}"}
  end

  test "create a board, save a draft, move it, inspect history and reconnect", %{
    conn: conn,
    arena: arena
  } do
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/arenas/#{arena.id}")
    result = view |> form("#tabula-form", name: "Second battle") |> render_submit()
    {:ok, view, _} = follow_redirect(result, signed)
    assert render(view) =~ "Second battle"
    assert has_element?(view, "#column-review", "Secutor")
    assert has_element?(view, "#tabula-board[tabindex='0']")
    assert has_element?(view, "#column-in_process", "Unavailable until battles")
    view |> form("#draft-form", title: "Write a plan") |> render_submit()
    board = List.last(Tabulae.list(arena.id))
    task = hd(Tabulae.tasks(board.id))
    assert has_element?(view, "#column-specs #task-#{task.id}")
    view |> element("button[aria-label='Edit Write a plan']") |> render_click()
    assert has_element?(view, "#draft-history", "Revision 1")
    view |> form("#draft-form", column: "todo") |> render_submit()
    assert has_element?(view, "[role=alert]", "ToDo needs")
    Foundation.broadcast()
    assert has_element?(view, "#draft-title-input[value='Write a plan']")
    assert has_element?(view, "[role=alert]", "ToDo needs")

    view
    |> form("#draft-form", description: "Plan the work", criteria: "Readable and tested")
    |> render_submit()

    assert has_element?(view, "#column-todo #task-#{task.id}")
    {:ok, again, _} = live(signed, "/arenas/#{arena.id}/tabulae/#{board.id}")
    again |> element("button[aria-label='Edit Write a plan']") |> render_click()
    assert has_element?(again, "#draft-history", "Revision 2")
    assert has_element?(again, "#draft-description", "Plan the work")
    assert has_element?(again, "#draft-history[phx-mounted*=ignore_attrs]")
    refute File.exists?(arena.path)
  end

  test "live updates preserve dirty text; stale editors and discard are explicit", %{
    conn: conn,
    arena: arena,
    board: board,
    path: path
  } do
    id = Ecto.UUID.generate()
    attrs = %{"title" => "Original", "description" => "", "criteria" => "", "column" => "specs"}
    Tabulae.save(Ecto.UUID.generate(), arena.id, board.id, id, 0, attrs)
    {:ok, view, _} = conn |> sign_in() |> live(path)
    view |> element("button[aria-label='Edit Original']") |> render_click()

    view
    |> form("#draft-form", title: "My unsaved title")
    |> render_change(%{"_unused_title" => ""})

    Tabulae.save(Ecto.UUID.generate(), arena.id, board.id, id, 1, %{
      attrs
      | "title" => "Other editor"
    })

    assert has_element?(view, "#draft-title-input[value='My unsaved title']")
    view |> form("#draft-form") |> render_submit()
    assert has_element?(view, "[role=alert]", "changed elsewhere")
    view |> element("button", "New draft") |> render_click()
    view |> element("button", "Keep editing") |> render_click()
    assert has_element?(view, "#draft-title-input[value='My unsaved title']")
    view |> element("button", "New draft") |> render_click()
    view |> element("button", "Discard unsaved edits") |> render_click()
    assert has_element?(view, "#draft-title-input[value='']")
    assert hd(Tabulae.tasks(board.id)).title == "Other editor"
  end

  test "recovered foreign forms keep text but cannot save into a different board", %{
    conn: conn,
    board: board,
    path: path
  } do
    {:ok, view, _} = conn |> sign_in() |> live(path)

    render_submit(view, "save", %{
      "task_id" => Ecto.UUID.generate(),
      "revision" => "0",
      "tabula_id" => board.id,
      "title" => "Recovered",
      "description" => "",
      "criteria" => "",
      "column" => "specs"
    })

    assert has_element?(view, "[role=alert]", "recovered form")
    assert has_element?(view, "#draft-title-input[value='Recovered']")
    view |> form("#draft-form") |> render_submit()
    assert Tabulae.tasks(board.id) == []
    assert has_element?(view, "[role=alert]", "recovered form")
  end

  test "auth, bad routes and forged input fail closed", %{
    conn: conn,
    arena: arena,
    board: board,
    path: path
  } do
    assert {:error, {:redirect, %{to: "/locked"}}} = live(conn, path)
    signed = sign_in(conn)

    for path <- [
          "/arenas/invalid",
          "/arenas/#{arena.id}/tabulae/invalid",
          "/arenas/#{Ecto.UUID.generate()}/tabulae/#{board.id}"
        ] do
      assert {:error, {:redirect, %{to: "/arenas"}}} = live(signed, path)
    end

    {:ok, index, _} = live(signed, "/arenas/#{arena.id}")
    render_submit(index, "save", %{})
    assert render(index) =~ "recovered form"
    {:ok, view, _} = live(signed, path)
    render_submit(view, "save", %{"title" => %{}})
    assert Tabulae.tasks(board.id) == []
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    render_submit(view, "create", %{"name" => "Unauthorized"})
    assert_redirect(view, "/locked")
    assert length(Tabulae.list(arena.id)) == 1
  end
end
