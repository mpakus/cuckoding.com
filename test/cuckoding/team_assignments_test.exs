defmodule Cuckoding.TeamAssignmentsTest do
  use Cuckoding.DataCase
  import Cuckoding.PlanningFixtures

  alias Cuckoding.{
    Arena,
    Command,
    Event,
    Foundation,
    Planning,
    Tabula,
    Tabulae,
    Team,
    TeamAdoption,
    TeamAssignments
  }

  setup do: planning_fixture()

  test "local Disconnect after executable replacement is atomic, scoped and replayable", ctx do
    before = Team.current()
    revision = Foundation.workspace().revision

    other =
      Repo.insert!(%Cuckoding.AgentConnection{
        id: Ecto.UUID.generate(),
        name: "Other account",
        kind: "codex",
        connection: %{"authorization" => "chatgpt", "status" => "checked"}
      })

    File.rename!(ctx.path, ctx.path <> ".old")
    File.write!(ctx.path, "#!/bin/sh\ntouch should-never-run\n")
    File.chmod!(ctx.path, 0o700)
    assert {:error, :version_required} = Foundation.verified_executable()
    key = Ecto.UUID.generate()
    {:ok, command} = Foundation.disconnect_agent(key, revision, true, "codex")
    assert command.state == "completed" and command.result == "local_only"
    assert command.payload["provider_logout"] == "not_attempted"
    assert Foundation.workspace().revision == revision + 1
    assert Foundation.workspace().connection["status"] == "disconnected"
    assert Foundation.workspace().connection["authorization"] == "unknown"
    assert Foundation.workspace().connection["models"] == []
    assert Repo.get!(Cuckoding.AgentConnection, other.id) == other
    assert Repo.get!(Cuckoding.TeamRevision, before.id) == before

    for scope <- [ctx.arena, ctx.board] do
      current = TeamAssignments.assigned(scope)
      assert hd(current.definition["roles"])["agent"] == ""

      assert hd(current.definition["roles"])["instructions"] ==
               hd(before.definition["roles"])["instructions"]
    end

    assert {:ok, nil} = Foundation.claim()
    refute File.exists?(Path.join(Path.dirname(ctx.path), "should-never-run"))
    count = Repo.aggregate(TeamAdoption, :count)
    assert {:ok, ^command} = Foundation.disconnect_agent(key, revision, true, "codex")
    assert Repo.aggregate(TeamAdoption, :count) == count
    assert {:error, :key_conflict} = Foundation.disconnect_agent(key, revision, true, other.id)

    # Re-verification must not turn replay of a local receipt into native logout.
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), revision + 1, ctx.path, true)
    {:ok, probe} = Foundation.claim()
    Foundation.finish(probe, %{"status" => "supported", "version" => "0.146.0"})
    assert {:ok, _} = Foundation.verified_executable()
    workspace = Foundation.workspace()
    assert {:ok, ^command} = Foundation.disconnect_agent(key, revision, true, "codex")
    assert Foundation.workspace() == workspace
    assert {:ok, nil} = Foundation.claim()
  end

  test "unverified local Disconnect retains confirmation, revision and global busy gates", ctx do
    File.rm!(ctx.path)
    revision = Foundation.workspace().revision
    before = Team.current()

    assert {:error, :invalid_disconnect} =
             Foundation.disconnect_agent(Ecto.UUID.generate(), revision, false, "codex")

    assert {:ok, %{state: "rejected", result: "stale_revision"}} =
             Foundation.disconnect_agent(Ecto.UUID.generate(), revision - 1, true, "codex")

    {:ok, _} = Foundation.discover(Ecto.UUID.generate(), revision)

    assert {:ok, %{state: "rejected", result: "profile_busy"}} =
             Foundation.disconnect_agent(Ecto.UUID.generate(), revision, true, "codex")

    assert Team.current() == before
    assert TeamAssignments.assigned(ctx.board) == before
  end

  test "a failed local Disconnect audit rolls back connection, roles and command together", ctx do
    File.rm!(ctx.path)
    before = Foundation.workspace()
    team = Team.current()
    key = Ecto.UUID.generate()

    Repo.query!("""
    CREATE TRIGGER reject_disconnect BEFORE INSERT ON events
    WHEN NEW.kind = 'agent.disconnect_completed'
    BEGIN SELECT RAISE(ABORT, 'disconnect rollback'); END
    """)

    assert_raise Exqlite.Error, fn ->
      Foundation.disconnect_agent(key, before.revision, true, "codex")
    end

    assert Foundation.workspace() == before
    assert Team.current() == team
    assert Repo.get(Command, key) == nil
    assert Repo.aggregate(TeamAdoption, :count) == 0
    Repo.query!("DROP TRIGGER reject_disconnect")

    assert {:ok, %{state: "completed"}} =
             Foundation.disconnect_agent(key, before.revision, true, "codex")
  end

  test "Disconnect unassigns current teams once, preserving defaults, other agents and history",
       ctx do
    old_default = Team.current()
    old_arena = TeamAssignments.assigned(ctx.arena)
    old_board = TeamAssignments.assigned(ctx.board)
    # The default can differ from both scopes; it must not become a scoped team on disconnect.
    roles =
      Team.editable(old_default)
      |> List.update_at(
        0,
        &Map.merge(&1, %{"agent" => "", "model_id" => "", "name" => "Default planner"})
      )

    {:ok, default} = Team.save(Ecto.UUID.generate(), old_default.id, roles)
    before_tasks = Tabulae.tasks(ctx.board.id)
    key = Ecto.UUID.generate()
    expected = Foundation.workspace().revision
    {:ok, command} = Foundation.authorize_codex(key, expected, :logout, true)
    assert command.state == "pending"
    assert {:ok, ^command} = Foundation.authorize_codex(key, expected, :logout, true)
    assert Repo.aggregate(TeamAdoption, :count) == 2
    assert Team.current().definition == default.definition

    for scope <- [ctx.arena, ctx.board] do
      current = TeamAssignments.assigned(scope)
      assert hd(current.definition["roles"])["agent"] == ""
      assert hd(current.definition["roles"])["model_id"] == ""

      assert hd(current.definition["roles"])["instructions"] ==
               hd(old_board.definition["roles"])["instructions"]
    end

    assert Repo.get!(Cuckoding.TeamRevision, old_board.id) == old_board
    assert Repo.get!(Cuckoding.TeamRevision, old_arena.id) == old_arena
    assert Tabulae.tasks(ctx.board.id) == before_tasks
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "logout_unconfirmed"})
    assert hd(TeamAssignments.assigned(ctx.board).definition["roles"])["agent"] == ""
  end

  test "a rejected logout does not change any team", ctx do
    before = Team.current()
    assigned = TeamAssignments.assigned(ctx.board)
    {:ok, command} = Foundation.authorize_codex(Ecto.UUID.generate(), 0, :logout, true)
    assert command.state == "rejected"
    assert Team.current() == before
    assert TeamAssignments.assigned(ctx.board) == assigned
    assert Repo.aggregate(TeamAdoption, :count) == 0
  end

  defp next_team(name) do
    previous = Team.current()
    roles = put_in(Team.editable(previous), [Access.at(0), "name"], name)
    {:ok, team} = Team.save(Ecto.UUID.generate(), previous.id, roles)
    team
  end

  defp adopt(scope, target, options \\ []) do
    arena? = match?(%Arena{}, scope)

    TeamAssignments.adopt(
      options[:key] || Ecto.UUID.generate(),
      if(arena?, do: scope.id, else: scope.arena_id),
      if(arena?, do: nil, else: scope.id),
      options[:expected] || TeamAssignments.assigned(scope).id,
      target.id,
      Keyword.get(options, :confirmed, true)
    )
  end

  test "Arena adoption only changes future boards; replay keeps original immutable receipt", %{
    arena: arena,
    board: board
  } do
    team = next_team("New planner")
    key = Ecto.UUID.generate()
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    assert {:ok, saved} = adopt(arena, team, key: key)
    assert_receive :updated
    assert {:ok, ^saved} = adopt(arena, team, key: key, expected: arena.team_revision_id)
    assert {:error, :key_conflict} = adopt(arena, team, key: key)
    assert TeamAssignments.assigned(arena) == team
    assert Repo.get!(Arena, arena.id) == arena
    assert Repo.get!(Tabula, board.id).team_revision_id == board.team_revision_id
    assert TeamAssignments.assigned(board).id == board.team_revision_id
    {:ok, new_board} = Tabulae.create(Ecto.UUID.generate(), arena.id, "After adoption")
    assert new_board.team_revision_id == team.id
    assert Repo.aggregate(TeamAdoption, :count) == 1
    assert Team.current() == team
    assert Foundation.workspace().revision == 2
    assert {:ok, nil} = Foundation.claim()
    assert hd(TeamAssignments.history(arena)).id == saved.id

    assert Enum.any?(
             Repo.all(Event),
             &(&1.kind == "team.adoption_completed" &&
                 &1.data["previous_revision"] == arena.team_revision_id)
           )
  end

  test "board changes refresh future planning consent and preserve earlier proposals and drafts",
       %{board: board} do
    old_setup = Planning.setup(board)

    {:ok, request} =
      Planning.request(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        "Original brief",
        old_setup.token,
        true
      )

    {:ok, claim} = Foundation.claim()
    {:ok, completed} = Foundation.finish(claim, planning_receipt(request.id))

    draft = imported_revision(board, request.id)

    before = Tabulae.tasks(board.id)
    team = next_team("Updated planner")
    assert {:ok, _} = adopt(board, team)
    assert TeamAssignments.assigned(board) == team
    assert Repo.get!(Command, request.id) == completed
    assert Repo.get!(Tabula, board.id).team_revision_id == board.team_revision_id
    assert Tabulae.tasks(board.id) == before
    assert hd(Tabulae.history(board.id, draft.task_id)) == draft
    assert Planning.proposal(completed)
    assert Planning.setup(board).token != old_setup.token

    assert {:ok, %{state: "rejected", result: "planning_setup_changed"}} =
             Planning.request(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               "Original brief",
               old_setup.token,
               true
             )

    setup = Planning.setup(board)

    assert {:ok, request} =
             Planning.request(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               "New brief",
               setup.token,
               true
             )

    assert request.payload["team_revision_id"] == team.id
    assert request.payload["role"]["name"] == "Updated planner"
    assert request.payload["grant"] == "scratch-read-only-v1"
  end

  test "confirmation, current default and scoped revision prevent stale or competing adoption", %{
    board: board
  } do
    first = next_team("First")
    target = next_team("Current")
    assert {:error, "adoption_confirmation_required"} = adopt(board, target, confirmed: false)
    assert {:error, "stale_adoption"} = adopt(board, first)
    key = Ecto.UUID.generate()
    assert {:error, "stale_adoption"} = adopt(board, target, expected: first.id, key: key)
    assert {:error, "stale_adoption"} = adopt(board, target, expected: first.id, key: key)

    results =
      for _ <- 1..2 do
        Task.async(fn -> adopt(board, target, expected: board.team_revision_id) end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:error, "stale_adoption"} in results
    assert {:error, "team_already_adopted"} = adopt(board, target)
    assert Repo.aggregate(TeamAdoption, :count) == 1
  end

  test "active planning blocks only its board, including cancellation until cleanup", %{
    arena: arena,
    board: board
  } do
    setup = Planning.setup(board)

    {:ok, command} =
      Planning.request(
        Ecto.UUID.generate(),
        arena.id,
        board.id,
        "Active brief",
        setup.token,
        true
      )

    target = next_team("Later planner")
    {:ok, other} = Tabulae.create(Ecto.UUID.generate(), arena.id, "Independent")
    assert {:error, "planning_active"} = adopt(board, target)
    assert {:ok, _} = adopt(other, target)
    assert {:ok, _} = adopt(arena, target)
    {:ok, claim} = Foundation.claim()
    assert {:error, "planning_active"} = adopt(board, target)
    Foundation.cancel_probe(command.id)
    assert {:error, "planning_active"} = adopt(board, target)
    Foundation.finish(claim, planning_receipt(command.id))
    assert {:ok, _} = adopt(board, target)
  end

  test "foreign scope, invalid arguments and history rewrites are refused", %{
    arena: arena,
    board: board
  } do
    target = next_team("New")
    other = Cuckoding.DataCase.arena_fixture()

    assert {:error, "scope_missing"} =
             TeamAssignments.adopt(
               Ecto.UUID.generate(),
               other.id,
               board.id,
               board.team_revision_id,
               target.id,
               true
             )

    assert {:error, "invalid_adoption"} =
             TeamAssignments.adopt(Ecto.UUID.generate(), arena.id, %{}, 1, target.id, true)

    assert {:error, "scope_missing"} =
             TeamAssignments.adopt(
               Ecto.UUID.generate(),
               Ecto.UUID.generate(),
               nil,
               1,
               target.id,
               true
             )

    assert {:ok, _} = adopt(board, target)
    assert {:error, _} = Repo.query("UPDATE team_adoptions SET team_revision_id = 1")
    assert {:error, _} = Repo.query("DELETE FROM team_adoptions")

    assert_raise Exqlite.Error, fn ->
      Repo.insert!(%TeamAdoption{
        arena_id: other.id,
        tabula_id: board.id,
        team_revision_id: target.id,
        command_id: Ecto.UUID.generate(),
        inserted_at: DateTime.utc_now()
      })
    end
  end

  test "an audit failure rolls back adoption and command together", %{board: board} do
    target = next_team("New")

    Repo.query!(
      "CREATE TEMP TRIGGER reject_adoption_event BEFORE INSERT ON events WHEN NEW.kind = 'team.adoption_completed' BEGIN SELECT RAISE(ABORT, 'fixture failure'); END"
    )

    key = Ecto.UUID.generate()
    assert_raise Exqlite.Error, fn -> adopt(board, target, key: key) end
    assert Repo.get(Command, key) == nil
    assert TeamAssignments.assigned(board).id == board.team_revision_id
    assert Repo.aggregate(TeamAdoption, :count) == 0
    Repo.query!("DROP TRIGGER reject_adoption_event")
  end
end
