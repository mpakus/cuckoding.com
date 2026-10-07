defmodule Cuckoding.PlanningTest do
  use Cuckoding.DataCase
  import Cuckoding.PlanningFixtures
  alias Cuckoding.{Command, DraftTaskRevision, Event, Foundation, Planning, Tabulae, Team}
  alias Ecto.Adapters.SQL
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
    assert revision.content["depends_on"] == []
    assert hd(Tabulae.tasks(board.id)).depends_on == []
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

  test "linked proposals import in order and retain citations without overwriting edited prerequisites",
       %{board: board} do
    claim = document_plan_fixture(board)
    assert claim.payload["contract"] == "brief-plan-v2"
    {:ok, plan} = Foundation.finish(claim, linked_planning_receipt(claim.id))
    assert plan.state == "completed"
    event = Repo.get_by!(Event, command_id: plan.id, kind: "planning.completed")
    assert event.data["dependency_count"] == 3
    assert event.data["citation_count"] == 3
    key = Ecto.UUID.generate()

    assert {:error, "prerequisites_not_imported"} =
             Tabulae.import_proposal(key, board.arena_id, board.id, plan.id, 2)

    assert Tabulae.tasks(board.id) == []

    {:ok, first} =
      Tabulae.import_proposal(Ecto.UUID.generate(), board.arena_id, board.id, plan.id, 0)

    {:ok, edited} =
      Tabulae.save(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        first.task_id,
        1,
        Map.put(first.content, "title", "User refined response")
      )

    {:ok, second} =
      Tabulae.import_proposal(Ecto.UUID.generate(), board.arena_id, board.id, plan.id, 1)

    assert second.content["depends_on"] == [first.task_id]

    assert {:error, "prerequisites_not_imported"} =
             Tabulae.import_proposal(key, board.arena_id, board.id, plan.id, 2)

    third_key = Ecto.UUID.generate()
    {:ok, third} = Tabulae.import_proposal(third_key, board.arena_id, board.id, plan.id, 2)
    assert third.content["depends_on"] == [first.task_id, second.task_id]

    assert {:ok, ^third} =
             Tabulae.import_proposal(third_key, board.arena_id, board.id, plan.id, 2)

    assert hd(Tabulae.history(board.id, first.task_id)) == edited
    assert Tabulae.source(board.id, second.task_id).documents == plan.payload["documents"]
    assert Tabulae.source(Ecto.UUID.generate(), second.task_id) == nil
    assert Planning.sources(plan, 5) == []
    assert Repo.get!(Command, claim.id) == plan
    refute inspect(Repo.all(Event)) =~ "docs/plan.md"
    assert {:ok, nil} = Foundation.claim()
  end

  test "malformed graph and source references, contract downgrade and unsent documents are discarded",
       %{board: board} do
    bad_tasks =
      hd(linked_planning_receipt(Ecto.UUID.generate())["proposal"]["tasks"])
      |> Map.put("sources", [])

    for {field, values} <- [
          {"depends_on", [[0], [1], [-1], ["0"], nil, %{}, [0, 0], [0.0]]},
          {"sources", [[0], [4], [-1], ["docs/plan.md"], nil, %{}, [0, 0], [0.0]]}
        ],
        bad <- values do
      {:ok, _} = request(board)
      {:ok, claim} = Foundation.claim()
      task = Map.put(bad_tasks, field, bad)
      receipt = put_in(planning_receipt(claim.id), ["proposal", "tasks"], [task])

      if field != "sources" or bad != [0],
        do: assert(Planning.normalize(Jason.encode!(receipt))["status"] == "invalid_response")

      assert {:ok, %{state: "failed", result: "invalid_response"} = saved} =
               Foundation.finish(claim, receipt)

      refute saved.payload["observation"]["proposal"]
    end

    for tasks <- [
          [
            %{
              "title" => "Old response",
              "description" => "Missing new contract",
              "criteria" => "Not accepted"
            }
          ],
          [
            Map.put(bad_tasks, "depends_on", [1]),
            %{bad_tasks | "title" => "Cycle", "depends_on" => [0]}
          ],
          [
            Map.put(bad_tasks, "sources", []),
            Map.drop(%{bad_tasks | "title" => "Mixed"}, ["depends_on", "sources"])
          ]
        ] do
      {:ok, _} = request(board)
      {:ok, claim} = Foundation.claim()
      receipt = put_in(planning_receipt(claim.id), ["proposal", "tasks"], tasks)

      assert {:ok, %{state: "failed", result: "invalid_response"}} =
               Foundation.finish(claim, receipt)
    end

    assert Tabulae.tasks(board.id) == []
  end

  test "legacy contracts and receipts remain importable without inferred citations", %{
    board: board
  } do
    payload =
      Planning.setup(board).payload
      |> Map.put("contract", "brief-plan-v1")
      |> Map.put("brief", "Legacy brief")

    legacy =
      Repo.insert!(%Command{
        id: Ecto.UUID.generate(),
        kind: "plan_tabula",
        expected_revision: 0,
        payload: payload
      })

    {:ok, claim} = Foundation.claim()

    receipt =
      update_in(
        planning_receipt(legacy.id),
        ["proposal", "tasks"],
        &Enum.map(&1, fn task -> Map.drop(task, ["depends_on", "sources"]) end)
      )

    assert {:ok, %{state: "completed"} = saved} = Foundation.finish(claim, receipt)
    assert Planning.proposal(saved) == receipt["proposal"]

    {:ok, task} =
      Tabulae.import_proposal(Ecto.UUID.generate(), board.arena_id, board.id, saved.id, 0)

    assert task.content["depends_on"] == []
    assert Tabulae.source(board.id, task.task_id).documents == []
    assert Repo.get!(Command, saved.id) == saved
  end

  test "six ordered tasks can cite four snapshot indices while larger sets fail closed" do
    receipt = planning_receipt(Ecto.UUID.generate())
    task = hd(receipt["proposal"]["tasks"])

    tasks =
      for index <- 0..5 do
        Map.merge(task, %{
          "title" => "Task #{index}",
          "depends_on" => Enum.take([0, 1, 2, 3, 4], index),
          "sources" => [0, 1, 2, 3]
        })
      end

    receipt = put_in(receipt, ["proposal", "tasks"], tasks)
    assert Planning.normalize(Jason.encode!(receipt)) == receipt

    for bad <- [
          tasks ++ [Map.put(task, "title", "Seventh")],
          List.replace_at(tasks, 5, Map.put(List.last(tasks), "depends_on", [0, 1, 2, 3, 4, 5])),
          List.replace_at(tasks, 5, Map.put(List.last(tasks), "sources", [0, 1, 2, 3, 4]))
        ] do
      assert Planning.normalize(Jason.encode!(put_in(receipt, ["proposal", "tasks"], bad)))[
               "status"
             ] == "invalid_response"
    end
  end

  test "import failure rolls back linked drafts and source receipts together", %{board: board} do
    claim = document_plan_fixture(board)
    {:ok, plan} = Foundation.finish(claim, linked_planning_receipt(claim.id))
    {:ok, _} = Tabulae.import_proposal(Ecto.UUID.generate(), board.arena_id, board.id, plan.id, 0)
    before = Tabulae.tasks(board.id)

    SQL.query!(
      Repo,
      "CREATE TEMP TRIGGER reject_import BEFORE INSERT ON events WHEN NEW.kind = 'planning.task_imported' BEGIN SELECT RAISE(ABORT, 'fixture'); END",
      []
    )

    key = Ecto.UUID.generate()

    assert_raise Exqlite.Error, fn ->
      Tabulae.import_proposal(key, board.arena_id, board.id, plan.id, 1)
    end

    assert Tabulae.tasks(board.id) == before
    assert Repo.get(Command, key) == nil
    assert map_size(Tabulae.imported(board.id)) == 1
    SQL.query!(Repo, "DROP TRIGGER reject_import", [])
  end
end
