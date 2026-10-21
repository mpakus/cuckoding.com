defmodule CuckodingWeb.DashboardLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  import Cuckoding.DashboardFixtures
  alias Cuckoding.{AgentConnection, BrowserToken, Command, Foundation, Repo, Tabulae}
  alias Cuckoding.Battles.Attempt

  test "global dashboard shows exact active worker, frozen progress and direct board navigation",
       ctx do
    f = fixture()

    Repo.insert!(%Attempt{
      id: Ecto.UUID.generate(),
      battle_id: f.battle.id,
      stage: "implementor",
      state: "running",
      role: "implementor",
      task_id: f.task.task_id,
      claim_token: Ecto.UUID.generate(),
      request: %{
        "role" => %{
          "name" => "Implementor",
          "kind" => "cursor",
          "agent_name" => "Cursor builder",
          "model" => "selected-grok",
          "private" => "secret-sentinel"
        }
      },
      deadline_at: f.battle.deadline_at
    })

    before = Repo.aggregate(Command, :count)
    {:ok, view, html} = ctx.conn |> sign_in() |> live("/")
    assert has_element?(view, "#dashboard-workers", "Implementor")
    assert has_element?(view, "#dashboard-workers", "Cursor builder")
    assert has_element?(view, "#dashboard-workers", "requested selected-grok")
    assert has_element?(view, "#arena-#{f.arena.id} progress[value='1'][max='1']")

    assert has_element?(
             view,
             "#arena-#{f.arena.id} a[href='/arenas/#{f.arena.id}/tabulae/#{f.board.id}']"
           )

    refute html =~ "secret-sentinel"
    assert Repo.aggregate(Command, :count) == before
  end

  test "activity pages stay fixed while reading and Follow latest resumes bounded live updates",
       ctx do
    for i <- 1..45, do: Foundation.record("task.notice_#{i}", %{"private" => "hidden-payload"})
    {:ok, view, html} = ctx.conn |> sign_in() |> live("/")
    assert has_element?(view, "#workspace-activity-entries li", "Task notice 45")
    refute html =~ "hidden-payload"

    assert length(
             view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#workspace-activity-entries li")
             |> LazyHTML.to_tree()
           ) == 20

    view |> element("#workspace-activity button[phx-click=older]") |> render_click()
    assert has_element?(view, "#workspace-activity-entries li", "Task notice 25")
    refute has_element?(view, "#workspace-activity-entries li", "Task notice 45")
    Foundation.record("task.notice_46")
    Foundation.broadcast()
    assert has_element?(view, "#workspace-activity", "Reading saved activity")
    assert has_element?(view, "#workspace-activity-entries li", "Task notice 25")
    refute has_element?(view, "#workspace-activity-entries li", "Task notice 46")
    view |> element("#workspace-activity button[phx-click=newer]") |> render_click()
    assert has_element?(view, "#workspace-activity-entries li", "Task notice 46")
    view |> element("#workspace-activity button[phx-click=follow]") |> render_click()
    assert has_element?(view, "#workspace-activity button[aria-pressed=true]", "Pause updates")
    assert has_element?(view, "#workspace-activity-entries[data-follow=true]")
  end

  test "setup and exact-board planning are visible without exposing inputs or changing work",
       ctx do
    f = fixture()
    other = fixture()

    agent =
      Repo.insert!(%AgentConnection{id: Ecto.UUID.generate(), name: "Planner", kind: "cursor"})

    command =
      Repo.insert!(%Command{
        id: Ecto.UUID.generate(),
        kind: "plan_tabula",
        state: "running",
        expected_revision: 0,
        payload: %{
          "arena_id" => f.arena.id,
          "tabula_id" => f.board.id,
          "agent_id" => agent.id,
          "kind" => "cursor",
          "model" => "saved-alias",
          "role" => %{"name" => "Speculator"},
          "brief" => "private-brief-canary"
        }
      })

    login =
      Repo.insert!(%Command{
        id: Ecto.UUID.generate(),
        kind: "login_codex",
        state: "cancelling",
        expected_revision: 0,
        payload: %{"url" => "private-url-canary"}
      })

    count = Repo.aggregate(Command, :count)
    signed = sign_in(ctx.conn)
    {:ok, global, html} = live(signed, "/")
    assert has_element?(global, "#dashboard-workers-#{command.id}", "Creating tasks")
    assert has_element?(global, "#dashboard-workers-#{command.id}", "Planner")
    assert has_element?(global, "#dashboard-workers-#{command.id}", "requested saved-alias")
    assert has_element?(global, "#dashboard-workers-#{login.id}", "Finishing cleanup")
    refute html =~ "private-brief-canary"
    refute html =~ "private-url-canary"
    {:ok, board, _} = live(signed, "/arenas/#{f.arena.id}/tabulae/#{f.board.id}")
    assert has_element?(board, "#board-activity summary", "1 / 1 battle tasks completed")
    assert has_element?(board, "#board-workers-#{command.id}", "Speculator")
    assert has_element?(board, "#board-saved-team", "Implementor")
    refute has_element?(board, "#board-workers-#{login.id}")
    refute board |> element("#board-activity") |> render() =~ "private-brief-canary"
    refute has_element?(board, "#board-activity form")

    Repo.update!(Ecto.Changeset.change(command, state: "completed"))
    Foundation.broadcast()
    refute has_element?(board, "#board-workers-#{command.id}")
    {:ok, again, _} = live(signed, "/arenas/#{f.arena.id}/tabulae/#{f.board.id}")
    refute has_element?(again, "#board-workers-#{command.id}")
    assert has_element?(again, "#board-activity summary", "1 / 1 battle tasks completed")
    {:ok, foreign, _} = live(signed, "/arenas/#{other.arena.id}/tabulae/#{other.board.id}")
    refute has_element?(foreign, "#board-workers-#{command.id}")
    assert Repo.aggregate(Command, :count) == count
  end

  test "pausing an empty activity feed also preserves it across updates", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live("/")
    view |> element("#workspace-activity button[phx-click=follow]") |> render_click()
    Foundation.record("task.arrived")
    Foundation.broadcast()
    refute has_element?(view, "#workspace-activity-entries li", "Task arrived")
    view |> element("#workspace-activity button[phx-click=follow]") |> render_click()
    assert has_element?(view, "#workspace-activity-entries li", "Task arrived")
  end

  test "Arena activity is scoped by the server and preserves a dirty task form", ctx do
    arena = Cuckoding.DataCase.arena_fixture()
    {:ok, board} = Tabulae.create(Ecto.UUID.generate(), arena.id, "Beta")
    for _ <- 1..23, do: Foundation.record("task.local", %{"arena_id" => arena.id})
    Foundation.record("task.foreign", %{"arena_id" => Ecto.UUID.generate()})
    {:ok, view, _} = ctx.conn |> sign_in() |> live("/arenas/#{arena.id}/tabulae/#{board.id}")
    assert has_element?(view, "#arena-activity-entries li", "Task local")
    refute has_element?(view, "#arena-activity-entries li", "Task foreign")
    view |> element("button[aria-label='Add task to Specs']") |> render_click()
    view |> form("#draft-form", title: "Keep my task") |> render_change()
    view |> element("#arena-activity button[phx-click=older]") |> render_click()
    Foundation.broadcast()
    assert has_element?(view, "#draft-title-input[value='Keep my task']")
    assert has_element?(view, "#arena-activity", "Reading saved activity")
  end

  test "expired component sessions cannot paginate activity or Arena summaries", ctx do
    for _ <- 1..23, do: Foundation.record("task.saved")
    {:ok, view, _} = ctx.conn |> sign_in() |> live("/")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("#workspace-activity button[phx-click=older]") |> render_click()
    assert_redirect(view, "/locked")
    for _ <- 1..22, do: Cuckoding.DataCase.arena_fixture()
    {:ok, view, _} = ctx.conn |> sign_in() |> live("/")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("#live-dashboard button[phx-click=older-arenas]") |> render_click()
    assert_redirect(view, "/locked")
  end
end
