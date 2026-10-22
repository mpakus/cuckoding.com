defmodule CuckodingWeb.ScopedTeamLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  import Cuckoding.PlanningFixtures
  alias Cuckoding.{BrowserToken, Foundation, Planning, Repo, Team, TeamAssignments}
  setup do: planning_fixture()

  test "board editor saves only here, preserves dirty input and reconnects", f do
    signed = sign_in(f.conn)
    board_path = "/arenas/#{f.arena.id}/tabulae/#{f.board.id}"
    path = board_path <> "/team"
    before = Team.current()
    {:ok, board, _} = live(signed, board_path)
    assert has_element?(board, "a[href='#{path}']", "Customize this board")
    {:ok, view, _} = live(signed, path)
    assert has_element?(view, "#team-scope-context", "Only #{f.board.name}")
    assert has_element?(view, "#team-next[href='#{board_path}#board-team']", "Back to")
    view |> form("#team-form", roles: %{speculator: %{name: "Only my board"}}) |> render_change()
    Foundation.broadcast()
    assert has_element?(view, "#name-speculator[value='Only my board']")
    view |> form("#team-form") |> render_submit()
    assert Team.current() == before
    assert hd(TeamAssignments.assigned(f.board).definition["roles"])["name"] == "Only my board"
    assert has_element?(view, "#team-next[href='#{board_path}#board-team']")
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#name-speculator[value='Only my board']")
    refute Foundation.pending?()
  end

  test "scoped form keys, stale scope patches, foreign routes and sessions refuse writes", f do
    signed = sign_in(f.conn)
    path = "/arenas/#{f.arena.id}/tabulae/#{f.board.id}/team"
    {:ok, view, _} = live(signed, path)
    view |> form("#team-form", roles: %{speculator: %{name: "Keep my text"}}) |> render_change()
    view |> form("#team-form") |> render_submit(%{"key" => "recovered"})
    assert has_element?(view, "#team-error", "form")
    assert TeamAssignments.assigned(f.board).id == f.board.team_revision_id
    assert has_element?(view, "#name-speculator[value='Keep my text']")
    render_patch(view, "/arenas/#{Ecto.UUID.generate()}/tabulae/#{f.board.id}/team")
    assert has_element?(view, "#team-scope-error")
    view |> form("#team-form") |> render_submit()
    assert TeamAssignments.assigned(f.board).id == f.board.team_revision_id
    assert has_element?(view, "#name-speculator[value='Keep my text']")
    render_patch(view, path)
    refute has_element?(view, "#team-scope-error")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> form("#team-form") |> render_submit()
    assert_redirect(view, "/locked")
    assert TeamAssignments.assigned(f.board).id == f.board.team_revision_id

    for invalid <- [
          "/arenas/invalid/team",
          "/arenas/#{Ecto.UUID.generate()}/tabulae/#{f.board.id}/team"
        ] do
      assert {:error, {:redirect, %{to: "/arenas"}}} = live(sign_in(f.conn), invalid)
    end
  end

  test "Arena editor clearly changes only new-board inheritance", f do
    path = "/arenas/#{f.arena.id}/team"
    {:ok, view, _} = f.conn |> sign_in() |> live(path)
    assert has_element?(view, "#team-scope-context", "New boards")
    before = Team.current()

    view
    |> form("#team-form", roles: %{speculator: %{name: "Future board planner"}})
    |> render_submit()

    assert Team.current() == before
    assert TeamAssignments.assigned(f.board) == before

    assert hd(TeamAssignments.assigned(f.arena).definition["roles"])["name"] ==
             "Future board planner"
  end

  test "active planning explains the disabled scoped Save and keeps the draft", f do
    path = "/arenas/#{f.arena.id}/tabulae/#{f.board.id}/team"
    {:ok, view, _} = f.conn |> sign_in() |> live(path)

    view
    |> form("#team-form", roles: %{speculator: %{name: "Wait for planning"}})
    |> render_change()

    setup = Planning.setup(f.board)

    {:ok, _} =
      Planning.request(
        Ecto.UUID.generate(),
        f.arena.id,
        f.board.id,
        "Current plan",
        setup.token,
        true
      )

    assert has_element?(view, "button[type=submit][disabled]", "Save team here")
    assert has_element?(view, "[role=status]", "This board is creating tasks")
    view |> form("#team-form") |> render_submit()
    assert has_element?(view, "#team-error", "Finish or cancel")
    assert has_element?(view, "#name-speculator[value='Wait for planning']")
    assert TeamAssignments.assigned(f.board).id == f.board.team_revision_id
  end
end
