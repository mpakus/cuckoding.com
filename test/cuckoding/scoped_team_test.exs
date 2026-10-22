defmodule Cuckoding.ScopedTeamTest do
  use Cuckoding.DataCase
  import Cuckoding.PlanningFixtures

  alias Cuckoding.{
    Command,
    Foundation,
    Planning,
    Tabulae,
    Team,
    TeamAdoption,
    TeamAssignments,
    TeamRevision
  }

  setup do: planning_fixture()

  defp save(scope, name, options \\ []) do
    current = TeamAssignments.assigned(scope)
    roles = put_in(Team.editable(current), [Access.at(0), "name"], name)

    Team.save(
      options[:key] || Ecto.UUID.generate(),
      options[:expected] || current.id,
      roles,
      Keyword.get(options, :confirmed, false),
      scope
    )
  end

  test "scoped Save appends exact authority without changing defaults or sibling boards", f do
    default = Team.current()
    old_setup = Planning.setup(f.board)
    {:ok, sibling} = Tabulae.create(Ecto.UUID.generate(), f.arena.id, "Sibling")
    key = Ecto.UUID.generate()
    assert {:ok, edited} = save(f.board, "Board planner", key: key)
    assert TeamAssignments.assigned(f.board) == edited
    assert TeamAssignments.assigned(sibling) == default
    assert TeamAssignments.assigned(f.arena) == default
    assert Team.current() == default
    assert edited not in Team.history()
    assert edited in Team.history(f.board)
    assert Repo.get!(TeamRevision, default.id) == default
    assert Repo.aggregate(TeamAdoption, :count) == 1
    assert Planning.setup(f.board).token != old_setup.token
    assert Planning.setup(f.board).payload["role"]["name"] == "Board planner"
    command = Repo.get!(Command, key)
    assert command.kind == "save_scoped_team"
    assert command.payload["arena_id"] == f.arena.id
    assert command.payload["tabula_id"] == f.board.id
    assert {:ok, ^edited} = save(f.board, "Board planner", key: key, expected: default.id)

    assert {:error, :key_conflict} =
             save(sibling, "Board planner", key: key, expected: default.id)

    assert {:ok, arena_team} = save(f.arena, "Arena planner")
    assert Team.current() == default
    assert TeamAssignments.assigned(f.board) == edited
    assert TeamAssignments.assigned(sibling) == default
    {:ok, inherited} = Tabulae.create(Ecto.UUID.generate(), f.arena.id, "After override")
    assert TeamAssignments.assigned(inherited) == arena_team
    assert hd(Team.history()) == default

    assert {:ok, _} =
             TeamAssignments.adopt(
               Ecto.UUID.generate(),
               f.arena.id,
               f.board.id,
               edited.id,
               default.id,
               true
             )

    assert TeamAssignments.assigned(f.board) == default
    assert {:ok, ^edited} = save(f.board, "Board planner", key: key, expected: default.id)
    assert TeamAssignments.assigned(f.board) == default
    refute Foundation.pending?()
  end

  test "scope, revision, planning, model and removal gates still apply", f do
    default = Team.current()

    assert {:error, "scope_missing"} =
             save(%{f.board | arena_id: Ecto.UUID.generate()}, "Foreign")

    assert {:error, "stale_team"} = save(f.board, "Stale", expected: default.id + 100)
    roles = put_in(Team.editable(default), [Access.at(0), "model_id"], "invented-model")

    assert {:error, "model_refresh_required"} =
             Team.save(Ecto.UUID.generate(), default.id, roles, false, f.board)

    setup = Planning.setup(f.board)

    {:ok, command} =
      Planning.request(
        Ecto.UUID.generate(),
        f.arena.id,
        f.board.id,
        "Active planning",
        setup.token,
        true
      )

    assert {:error, "planning_active"} = save(f.board, "Busy")
    assert {:ok, _} = save(f.arena, "Future boards")
    {:ok, claim} = Foundation.claim()
    Foundation.cancel_probe(command.id)
    assert {:error, "planning_active"} = save(f.board, "Cancelling")
    Foundation.finish(claim, planning_receipt(command.id))
    assert {:ok, _} = save(f.board, "Settled")
    assert Team.current() == default
  end

  test "audit failure rolls back the scoped revision, adoption and command", f do
    key = Ecto.UUID.generate()
    before = {Repo.aggregate(TeamRevision, :count), Repo.aggregate(TeamAdoption, :count)}

    Repo.query!(
      "CREATE TEMP TRIGGER reject_scoped_team BEFORE INSERT ON events WHEN NEW.kind = 'team.scoped_saved' BEGIN SELECT RAISE(ABORT, 'fixture'); END"
    )

    assert_raise Exqlite.Error, fn -> save(f.board, "Never committed", key: key) end
    assert Repo.get(Command, key) == nil
    assert before == {Repo.aggregate(TeamRevision, :count), Repo.aggregate(TeamAdoption, :count)}
    Repo.query!("DROP TRIGGER reject_scoped_team")
    assert {:ok, _} = save(f.board, "Committed", key: key)
  end

  test "competing edits and custom removal keep revisions and history intact", f do
    before = Team.current()

    results =
      for name <- ["First scoped", "Second scoped"] do
        Task.async(fn -> save(f.board, name, expected: before.id) end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:error, "stale_team"} in results
    current = TeamAssignments.assigned(f.board)
    custom = Map.put(Team.custom_role(), "name", "Researcher")

    {:ok, added} =
      Team.save(
        Ecto.UUID.generate(),
        current.id,
        Team.editable(current) ++ [custom],
        false,
        f.board
      )

    assert {:error, "removal_confirmation_required"} =
             Team.save(Ecto.UUID.generate(), added.id, Team.editable(current), false, f.board)

    assert {:ok, _} =
             Team.save(Ecto.UUID.generate(), added.id, Team.editable(current), true, f.board)

    assert Repo.get!(TeamRevision, added.id) == added
    assert Team.current() == before
  end

  test "completed planning receipts and automatic cards retain the previous frozen team", f do
    setup = Planning.setup(f.board)

    {:ok, request} =
      Planning.request(
        Ecto.UUID.generate(),
        f.arena.id,
        f.board.id,
        "Original plan",
        setup.token,
        true
      )

    {:ok, claim} = Foundation.claim()
    {:ok, completed} = Foundation.finish(claim, planning_receipt(request.id))
    cards = Tabulae.tasks(f.board.id)
    assert {:ok, scoped} = save(f.board, "Future planner")
    assert Repo.get!(Command, request.id) == completed
    assert Tabulae.tasks(f.board.id) == cards
    assert completed.payload["team_revision_id"] != scoped.id
    assert Planning.setup(f.board).payload["team_revision_id"] == scoped.id

    assert {:error, "stale_adoption"} =
             TeamAssignments.adopt(
               Ecto.UUID.generate(),
               f.arena.id,
               f.board.id,
               scoped.id,
               scoped.id,
               true
             )
  end

  test "Disconnect retains scoped instructions and the independent default", f do
    {:ok, scoped} = save(f.board, "Board-only planner")
    default = Team.current()
    roles = put_in(Team.editable(default), [Access.at(0), "agent"], "")
    roles = put_in(roles, [Access.at(0), "model_id"], "")
    {:ok, default} = Team.save(Ecto.UUID.generate(), default.id, roles)
    File.rm!(f.path)

    {:ok, _} =
      Foundation.disconnect_agent(
        Ecto.UUID.generate(),
        Foundation.workspace().revision,
        true,
        "codex"
      )

    current = TeamAssignments.assigned(f.board)
    assert hd(current.definition["roles"])["name"] == "Board-only planner"
    assert hd(current.definition["roles"])["agent"] == ""
    assert Team.current() == default
    assert Repo.get!(TeamRevision, scoped.id) == scoped
  end
end
