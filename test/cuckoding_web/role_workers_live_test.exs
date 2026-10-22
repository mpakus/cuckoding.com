defmodule CuckodingWeb.RoleWorkersLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  import Cuckoding.BattleFixtures
  import Cuckoding.RoleSlotFixtures
  alias Cuckoding.{BrowserToken, Foundation, Repo, Team, TeamAssignments}

  setup do: fixture()

  test "optional worker uses the shared selectors and preserves primary choices and dirty text",
       ctx do
    id = additional_connection()
    path = "/arenas/#{ctx.board.arena_id}/tabulae/#{ctx.board.id}/team"
    original = Team.current()
    signed = sign_in(ctx.conn)
    {:ok, view, _} = live(signed, path)
    assert has_element?(view, "#role-workers-implementor[phx-mounted*=ignore_attrs]:not([open])")
    assert has_element?(view, "label[for=parallel_agent-implementor]")
    assert has_element?(view, "#parallel_model-implementor[disabled]")

    view
    |> form("#team-form",
      roles: %{
        implementor: %{
          name: "Two writers",
          instructions: "Keep my instructions",
          parallel_agent: id
        }
      }
    )
    |> render_change()

    assert has_element?(view, "#model-implementor option[selected][value=test-id]")
    assert has_element?(view, "#parallel_model-implementor option[selected][value='']")
    assert has_element?(view, "#parallel_model-implementor option[value=worker-model]")
    Foundation.broadcast()
    assert has_element?(view, "#name-implementor[value='Two writers']")
    assert has_element?(view, "#instructions-implementor", "Keep my instructions")

    view
    |> form("#team-form",
      roles: %{implementor: %{parallel_agent: id, parallel_model_id: "worker-model"}}
    )
    |> render_submit()

    saved = TeamAssignments.assigned(ctx.board)
    role = Enum.at(saved.definition["roles"], 1)
    assert role["parallel_agent"] == id and role["parallel_model"] == "test-model"
    assert role["model_id"] == "test-id"
    assert Team.current() == original
    assert has_element?(view, "#parallel_model-implementor option[selected][value=worker-model]")
    assert has_element?(view, "#team-history", "worker 2")
    view |> form("#team-form", roles: %{implementor: %{parallel_agent: ""}}) |> render_change()
    assert has_element?(view, "#parallel_model-implementor option[selected][value='']")
    assert has_element?(view, "#model-implementor option[selected][value=test-id]")
    view |> form("#team-form") |> render_submit()

    assert Enum.at(TeamAssignments.assigned(ctx.board).definition["roles"], 1)["parallel_agent"] ==
             ""

    refute Foundation.pending?()
  end

  test "Start Inspect shows exact frozen extra bindings", ctx do
    id = additional_connection()
    assign_worker(ctx.board, id)
    battle = start(ctx.board)

    {:ok, view, _} =
      ctx.conn |> sign_in() |> live("/arenas/#{ctx.board.arena_id}/tabulae/#{ctx.board.id}")

    assert has_element?(view, "#battle-frozen-team", "Implementor · worker 2")
    assert has_element?(view, "#battle-frozen-team", "Second writer")
    assert has_element?(view, "#battle-frozen-team", "test-model")
    command_id = hd(battle.snapshot["parallel_team"])["connection_command_id"]
    refute render(view) =~ command_id
    refute Foundation.pending?()
  end

  test "cleared optional slots do not require adopting equivalent role settings", ctx do
    id = additional_connection()
    original = Team.current()

    roles =
      List.update_at(
        Team.editable(original),
        1,
        &Map.merge(&1, %{"parallel_agent" => id, "parallel_model_id" => "worker-model"})
      )

    {:ok, with_worker} = Team.save(Ecto.UUID.generate(), original.id, roles)

    cleared =
      List.update_at(
        Team.editable(with_worker),
        1,
        &Map.merge(&1, %{"parallel_agent" => "", "parallel_model_id" => ""})
      )

    {:ok, without_worker} = Team.save(Ecto.UUID.generate(), with_worker.id, cleared)
    assert without_worker.definition["version"] == 2
    assert TeamAssignments.assigned(ctx.board) == original

    {:ok, view, _} =
      ctx.conn |> sign_in() |> live("/arenas/#{ctx.board.arena_id}/tabulae/#{ctx.board.id}")

    assert has_element?(view, "#scope-team", "matches your saved Team settings")
    refute has_element?(view, "#scope-team-form")
    assert Repo.get!(Cuckoding.TeamRevision, original.id) == original
  end

  test "foreign and expired worker forms cannot change scope or start usage", ctx do
    id = additional_connection()
    path = "/arenas/#{ctx.board.arena_id}/tabulae/#{ctx.board.id}/team"
    {:ok, view, _} = ctx.conn |> sign_in() |> live(path)
    before = TeamAssignments.assigned(ctx.board)

    render_change(view, "change", %{
      "roles" => %{"implementor" => %{"name" => "Kept draft", "parallel_agent" => id}}
    })

    render_submit(view, "save", %{
      "key" => "foreign",
      "roles" => %{"implementor" => %{"parallel_model_id" => "worker-model"}}
    })

    assert has_element?(view, "#team-error", "form")
    assert has_element?(view, "#name-implementor[value='Kept draft']")
    assert TeamAssignments.assigned(ctx.board) == before
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> form("#team-form") |> render_submit()
    assert_redirect(view, "/locked")
    assert TeamAssignments.assigned(ctx.board) == before
    refute Foundation.pending?()
  end
end
