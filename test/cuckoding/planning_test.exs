defmodule Cuckoding.PlanningTest do
  use Cuckoding.DataCase
  import Cuckoding.PlanningFixtures
  alias Cuckoding.{Command, DraftTaskRevision, Event, Foundation, Planning, Tabulae, Team}
  setup do: planning_fixture()

  defp request(board, options \\ []) do
    Planning.request(
      options[:key] || Ecto.UUID.generate(),
      board.arena_id,
      board.id,
      options[:brief] || "Build a small feature",
      options[:token] || Planning.setup(board).token,
      Keyword.get(options, :confirmed, true)
    )
  end

  test "consent freezes the board team and excludes concurrent provider operations", %{
    board: board
  } do
    assert {:error, "planning_confirmation_required"} = request(board, confirmed: false)

    assert {:error, "planning_confirmation_required"} =
             request(board, brief: String.duplicate("x", 8001))

    {:ok, command} = request(board)
    assert command.state == "pending"
    assert {:ok, ^command} = request(board, key: command.id)
    assert {:error, :key_conflict} = request(board, key: command.id, brief: "Different")
    assert command.payload["team_revision_id"] == board.team_revision_id
    refute command.payload["path"]

    assert {:ok, %{state: "rejected", result: "profile_busy"}} =
             Foundation.authorize_codex(Ecto.UUID.generate(), 2, :logout, true)

    for _ <- 1..6, do: request(board)
    assert hd(Planning.history(board.id)).id == command.id
    Foundation.cancel_probe(command.id)
    team = Team.current()

    {:ok, _} =
      Team.save(
        Ecto.UUID.generate(),
        team.id,
        Enum.map(Team.editable(team), &Map.put(&1, "instructions", "Changed future team"))
      )

    {:ok, next} = request(board)
    assert next.payload["role"] == command.payload["role"]
  end

  test "stale setup consent and unavailable models fail closed", %{board: board, path: path} do
    token = Planning.setup(board).token
    conn = Map.put(Foundation.workspace().connection, "command_id", Ecto.UUID.generate())
    Foundation.workspace() |> Ecto.Changeset.change(connection: conn) |> Repo.update!()

    assert {:ok, %{state: "rejected", result: "planning_setup_changed"}} =
             request(board, token: token)

    File.write!(path, "#!/bin/sh\nexit 2\n# changed\n")
    assert Planning.setup(board).token == nil
    assert {:ok, %{state: "rejected"}} = request(board, token: token)
  end

  test "a public proposal survives reload and imports exactly once with scoped provenance", %{
    board: board
  } do
    {:ok, command} = request(board)
    {:ok, claim} = Foundation.claim()
    result = Map.put(planning_receipt(command.id), "reasoning", "hidden-canary")
    {:ok, saved} = Foundation.finish(claim, result)
    assert saved.state == "completed"
    assert Planning.proposal(hd(Planning.history(board.id))) == result["proposal"]
    refute inspect(Repo.all(Command)) =~ "hidden-canary"
    refute inspect(Repo.all(Event)) =~ "Implement the brief"
    assert Tabulae.tasks(board.id) == []
    key = Ecto.UUID.generate()
    assert {:ok, revision} = Tabulae.import_proposal(key, board.arena_id, board.id, command.id, 0)

    assert {:ok, ^revision} =
             Tabulae.import_proposal(key, board.arena_id, board.id, command.id, 0)

    assert {:error, "already_imported"} =
             Tabulae.import_proposal(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               command.id,
               0
             )

    assert revision.content["column"] == "specs"
    assert Repo.get!(Command, revision.command_id).payload["proposal_id"] == command.id
    {:ok, other} = Tabulae.create(Ecto.UUID.generate(), board.arena_id, "Other")

    assert {:error, "invalid_proposal"} =
             Tabulae.import_proposal(
               Ecto.UUID.generate(),
               board.arena_id,
               other.id,
               command.id,
               0
             )

    assert {:ok, %{revision: 2}} =
             Tabulae.save(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               revision.task_id,
               1,
               Map.put(revision.content, "title", "User edited")
             )

    assert Repo.aggregate(DraftTaskRevision, :count) == 2
  end

  test "malformed and unbound proposals never persist or import", %{board: board} do
    for change <- [:duplicate, :extra, :oversize, :model, :request] do
      {:ok, command} = request(board)
      {:ok, claim} = Foundation.claim()
      receipt = planning_receipt(command.id)

      bad =
        case change do
          :duplicate ->
            put_in(
              receipt,
              ["proposal", "tasks"],
              List.duplicate(hd(receipt["proposal"]["tasks"]), 2)
            )

          :extra ->
            put_in(receipt, ["proposal", "command"], "rm anything")

          :oversize ->
            put_in(receipt, ["proposal", "summary"], String.duplicate("x", 2001))

          :model ->
            Map.put(receipt, "observed_model", "different")

          :request ->
            Map.put(receipt, "request_id", Ecto.UUID.generate())
        end

      assert {:ok, %{state: "failed"} = saved} = Foundation.finish(claim, bad)
      refute Planning.proposal(saved)
      refute saved.payload["observation"]["proposal"]

      assert {:error, "invalid_proposal"} =
               Tabulae.import_proposal(
                 Ecto.UUID.generate(),
                 board.arena_id,
                 board.id,
                 command.id,
                 0
               )
    end
  end

  test "cancellation excludes late success; lease expiry never repeats inference", %{board: board} do
    {:ok, command} = request(board)
    {:ok, claim} = Foundation.claim()
    Foundation.cancel_probe(command.id)
    assert Foundation.pending?()

    assert {:ok, %{state: "cancelled"} = cancelled} =
             Foundation.finish(claim, planning_receipt(command.id))

    refute Planning.proposal(cancelled)
    {:ok, _} = request(board)
    {:ok, claim} = Foundation.claim(1000)

    assert {:ok, %{state: "failed", result: "interrupted", attempts: 1}} =
             Foundation.claim(141_001)

    assert {:ok, nil} = Foundation.claim(141_002)
    assert {:error, :lost_claim} = Foundation.finish(claim, planning_receipt(claim.id))
    assert Tabulae.tasks(board.id) == []
  end
end
