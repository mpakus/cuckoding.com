defmodule CuckodingWeb.PlanningLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  import Cuckoding.PlanningFixtures
  alias Cuckoding.{Foundation, Planning, Tabulae}
  setup do: planning_fixture()

  test "brief consent, progress, durable proposals and import preserve unrelated draft text", %{
    conn: conn,
    board: board
  } do
    signed = sign_in(conn)
    path = "/arenas/#{board.arena_id}/tabulae/#{board.id}"
    {:ok, view, _} = live(signed, path)
    assert has_element?(view, "#brief-planning[phx-mounted*=ignore_attrs]")
    view |> form("#draft-form", title: "Unsaved manual task") |> render_change()
    view |> form("#planning-form", brief: "A small feature") |> render_submit()
    assert has_element?(view, "#planning-error", "confirm provider usage")
    view |> form("#planning-form", confirmed: "true") |> render_submit()
    command = hd(Planning.history(board.id))
    assert command.state == "pending"
    assert has_element?(view, "#plan-#{command.id}", "Codex · test-model")
    assert has_element?(view, "#plan-#{command.id} button", "Cancel planning")
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, planning_receipt(command.id))
    assert has_element?(view, "#plan-#{command.id}", "A proposed task")

    view
    |> element("#plan-#{command.id} button", "Add to Specs")
    |> render_click(%{"index" => %{}})

    assert Tabulae.tasks(board.id) == []
    view |> element("#plan-#{command.id} button", "Add to Specs") |> render_click()
    task = hd(Tabulae.tasks(board.id))
    assert has_element?(view, "#column-specs #task-#{task.id}")
    assert has_element?(view, "#draft-title-input[value='Unsaved manual task']")
    assert has_element?(view, "#planning-brief", "A small feature")
    assert has_element?(view, "#plan-#{command.id} button[disabled]", "Added to Specs")
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#plan-#{command.id}", "A proposed task")
    assert has_element?(again, "#plan-#{command.id} button[disabled]", "Added to Specs")
  end

  test "changed connection clears consent while retaining the brief; cancellation remains visible",
       %{conn: conn, board: board} do
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{board.arena_id}/tabulae/#{board.id}")
    view |> form("#planning-form", brief: "Keep this brief", confirmed: "true") |> render_change()
    connection = Map.put(Foundation.workspace().connection, "command_id", Ecto.UUID.generate())

    Foundation.workspace()
    |> Ecto.Changeset.change(connection: connection)
    |> Cuckoding.Repo.update!()

    Foundation.broadcast()
    refute has_element?(view, "#planning-form input[name=confirmed][checked]")
    assert has_element?(view, "#planning-brief", "Keep this brief")
    view |> form("#planning-form", confirmed: "true") |> render_submit()
    command = hd(Planning.history(board.id))
    {:ok, claim} = Foundation.claim()
    view |> element("#plan-#{command.id} button", "Cancel planning") |> render_click()
    assert has_element?(view, "#plan-#{command.id}", "cancelling")
    Foundation.finish(claim, planning_receipt(command.id))
    assert has_element?(view, "#plan-#{command.id}", "Planning cancelled")
    refute has_element?(view, "#plan-#{command.id}", "A proposed task")
  end
end
