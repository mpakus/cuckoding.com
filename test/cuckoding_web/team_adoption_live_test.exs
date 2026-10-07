defmodule CuckodingWeb.TeamAdoptionLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  import Cuckoding.PlanningFixtures
  alias Cuckoding.{BrowserToken, Foundation, Repo, Tabulae, Team, TeamAssignments}
  setup do: planning_fixture()

  defp next_team(name) do
    previous = Team.current()

    {:ok, team} =
      Team.save(
        Ecto.UUID.generate(),
        previous.id,
        put_in(Team.editable(previous), [Access.at(0), "name"], name)
      )

    team
  end

  test "adopt with explicit preview and retain unsaved text, updated labels and history after reconnect",
       %{conn: conn, board: board} do
    signed = sign_in(conn)
    path = "/arenas/#{board.arena_id}/tabulae/#{board.id}"
    {:ok, view, _} = live(signed, path)
    view |> form("#planning-form", brief: "Keep my brief", confirmed: "true") |> render_change()
    view |> form("#draft-form", title: "Unsaved task") |> render_change()
    team = next_team("New planner")
    assert has_element?(view, "#scope-team", "Proposed saved default")
    assert has_element?(view, "#scope-team", "test-id · test-model")
    view |> form("#scope-team-form") |> render_submit()
    assert has_element?(view, "#scope-team [role=alert]", "confirmation is missing")
    Foundation.broadcast()
    assert has_element?(view, "#scope-team [role=alert]")
    view |> form("#scope-team-form", confirmed: "true") |> render_submit()
    assert TeamAssignments.assigned(board).id == team.id
    assert has_element?(view, "#column-specs", "New planner")
    assert has_element?(view, "#planning-brief", "Keep my brief")
    refute has_element?(view, "#planning-form input[name=confirmed][checked]")
    assert has_element?(view, "#draft-title-input[value='Unsaved task']")
    assert has_element?(view, "#scope-team-history", "Adopted team")
    assert has_element?(view, "#scope-team[phx-mounted*=ignore_attrs]")
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#column-specs", "New planner")
    assert has_element?(again, "#scope-team", "latest saved default")
    assert Tabulae.tasks(board.id) == []
  end

  test "changed defaults clear confirmation; stale submitted forms and expired sessions cannot adopt",
       %{conn: conn, board: board} do
    first = next_team("First")
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{board.arena_id}/tabulae/#{board.id}")
    view |> form("#scope-team-form", confirmed: "true") |> render_change()
    next_team("Second")
    refute has_element?(view, "#scope-team-form input[name=confirmed][checked]")

    view
    |> form("#scope-team-form", confirmed: "true")
    |> render_submit(%{"target" => to_string(first.id)})

    assert TeamAssignments.assigned(board).id == board.team_revision_id
    assert has_element?(view, "#scope-team [role=alert]")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> form("#scope-team-form", confirmed: "true") |> render_submit()
    assert_redirect(view, "/locked")
    assert TeamAssignments.assigned(board).id == board.team_revision_id
  end

  test "Arena settings change only new board inheritance; active planning exposes the blocking reason",
       %{conn: conn, arena: arena, board: board} do
    team = next_team("Arena planner")
    signed = sign_in(conn)
    {:ok, settings, _} = live(signed, "/arenas/#{arena.id}")
    settings |> form("#scope-team-form", confirmed: "true") |> render_submit()
    assert has_element?(settings, "#tabula-form", "Inherits Arena team revision #{team.id}")
    result = settings |> form("#tabula-form", name: "New board") |> render_submit()
    {:ok, new_view, _} = follow_redirect(result, signed)
    assert has_element?(new_view, "#column-specs", "Arena planner")
    {:ok, old_view, _} = live(signed, "/arenas/#{arena.id}/tabulae/#{board.id}")
    assert has_element?(old_view, "#column-specs", "Speculator")

    old_view
    |> form("#planning-form", brief: "Plan something", confirmed: "true")
    |> render_submit()

    assert has_element?(old_view, "#scope-team button[disabled]", "Adopt saved team")
    assert has_element?(old_view, "#scope-team", "Finish or cancel")
  end
end
