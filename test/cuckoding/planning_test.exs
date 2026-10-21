defmodule Cuckoding.PlanningTest do
  use Cuckoding.DataCase
  import Cuckoding.PlanningFixtures
  alias Cuckoding.{Command, DraftTaskRevision, Event, Foundation, Planning, Tabulae, Team}
  alias Ecto.Adapters.SQL
  setup do: planning_fixture()

  test "the assigned Cursor Speculator generates cards without a Codex fallback", %{board: board} do
    %{agent: agent, board: board} = cursor_speculator(board)
    setup = Planning.setup(board)
    assert setup.token
    assert setup.payload["agent_id"] == agent.id
    assert setup.payload["kind"] == "cursor"
    assert setup.payload["grant"] == "cursor-plan-no-tools-v1"
    {:ok, command} = request(board)
    {:ok, claim} = Foundation.claim()

    assert {:ok, %{state: "completed"} = saved} =
             Foundation.finish(claim, cursor_planning_receipt(command.id))

    assert length(Tabulae.tasks(board.id)) == 1
    assert saved.payload["observation"]["runtime_model"] == "fixture-base"
    assert saved.payload["observation"]["runtime_parameters"] == %{"effort" => "xhigh"}
    assert saved.payload["agent_id"] == agent.id
  end

  test "Cursor planning rejects mismatched grants, models and runtime metadata", %{board: board} do
    %{board: board} = cursor_speculator(board)

    for change <- [:grant, :model, :runtime, :cleanup, :tools, :transport, :missing_cleanup] do
      {:ok, command} = request(board)
      {:ok, claim} = Foundation.claim()
      good = cursor_planning_receipt(command.id)

      bad =
        case change do
          :grant -> Map.put(good, "grant", "host-task-tools-v1")
          :model -> Map.put(good, "observed_model", "another")
          :runtime -> Map.put(good, "runtime_parameters", %{"raw" => "not public metadata"})
          :cleanup -> Map.put(good, "cleanup_verified", false)
          :tools -> Map.put(good, "tools", [%{"tool" => "read_file"}])
          :transport -> Map.put(good, "transport", "unknown-transport")
          :missing_cleanup -> Map.delete(good, "cleanup_verified")
        end

      assert {:ok, %{state: "failed"} = saved} = Foundation.finish(claim, bad)
      refute Planning.proposal(saved)
    end

    assert Tabulae.tasks(board.id) == []
  end

  test "planning dispatch reaches only the frozen Cursor profile and native plan operation", %{
    board: board,
    path: path
  } do
    %{agent: agent, board: board} = cursor_speculator(board)
    {:ok, command} = request(board)
    {:ok, claim} = Foundation.claim()
    helper = Path.join(Path.dirname(path), "native-helper")
    old_helper = Application.get_env(:cuckoding, :native_helper)
    Application.put_env(:cuckoding, :native_helper, helper)
    on_exit(fn -> Application.put_env(:cuckoding, :native_helper, old_helper) end)
    receipt = cursor_planning_receipt(command.id)

    File.write!(helper, """
    #!/usr/bin/python3
    import json,sys
    request=json.loads(sys.stdin.readline())
    assert sys.argv[1]=='--plan-cursor-brief'
    assert sys.argv[3].endswith('/agents/#{agent.id}')
    assert sys.argv[5]=='cursor-fixture'
    assert set(request)=={'request_id','brief','instructions','documents','contract'}
    assert request['contract']=='brief-plan-v3'
    print(json.dumps(json.loads(#{Jason.encode!(Jason.encode!(receipt))})))
    """)

    File.chmod!(helper, 0o700)
    result = Planning.execute(claim)
    assert result == receipt
    assert {:ok, %{state: "completed"}} = Foundation.finish(claim, result)
    assert Planning.execute(claim) == %{"status" => "cancelled"}
    assert length(Tabulae.tasks(board.id)) == 1
  end

  test "catalog age alone keeps the assigned Speculator usable, without allowing new selections",
       %{board: board} do
    workspace = Foundation.workspace()
    connection = Map.put(workspace.connection, "fetched_at", "2000-01-01T00:00:00Z")
    Repo.update!(Ecto.Changeset.change(workspace, connection: connection))
    assert Team.catalog("codex").status == :catalog_stale
    setup = Planning.setup(board)
    assert setup.token
    assert Foundation.saved_binding_current?(setup.payload)
    refute Foundation.model_check_current?(setup.payload)
    assert {:ok, %{state: "pending"}} = request(board)
    {:ok, claim} = Foundation.claim()
    assert {:ok, %{state: "completed"}} = Foundation.finish(claim, planning_receipt(claim.id))

    assert {:ok, %{state: "rejected", result: "model_refresh_required"}} =
             Foundation.save_agent_models(
               Ecto.UUID.generate(),
               workspace.revision,
               connection["command_id"],
               ["test-id"]
             )

    Repo.update!(
      Ecto.Changeset.change(Foundation.workspace(),
        connection: Map.put(connection, "catalog_status", "stale")
      )
    )

    assert Planning.setup(board).token == nil
    refute Foundation.saved_binding_current?(setup.payload)
  end

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

  test "a public proposal automatically creates cards once with scoped provenance", %{
    board: board
  } do
    {:ok, command} = request(board)
    {:ok, claim} = Foundation.claim()

    criteria =
      "Expected: document the feature. Check: inspect README.md for the documented behavior."

    receipt =
      put_in(
        planning_receipt(command.id),
        ["proposal", "tasks", Access.at(0), "criteria"],
        criteria
      )

    result = Map.put(receipt, "reasoning", "hidden-canary")
    {:ok, saved} = Foundation.finish(claim, result)
    assert saved.state == "completed"
    assert Planning.proposal(hd(Planning.history(board.id))) == result["proposal"]
    refute inspect(Repo.all(Command)) =~ "hidden-canary"
    refute inspect(Repo.all(Event)) =~ "Implement the brief"
    assert length(Tabulae.tasks(board.id)) == 1
    revision = imported_revision(board, command.id)
    key = revision.command_id

    assert {:error, :lost_claim} = Foundation.finish(claim, result)
    assert {:ok, nil} = Foundation.claim()

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

    assert revision.content["criteria"] == criteria
    assert hd(Tabulae.tasks(board.id)).criteria == criteria
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

    # A newly consented analysis appends a graph; it cannot replace an edited card.
    {:ok, next} = request(board)
    {:ok, next_claim} = Foundation.claim()
    {:ok, _} = Foundation.finish(next_claim, planning_receipt(next.id))
    assert length(Tabulae.tasks(board.id)) == 2
    assert hd(Tabulae.history(board.id, revision.task_id)).content["title"] == "User edited"
    assert Repo.get!(Command, command.id) == saved
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
    claim = document_plan_fixture(board) |> legacy_plan_fixture()
    assert claim.payload["contract"] == "brief-plan-v3"
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
          {"sources", [[0], [16], [-1], ["docs/plan.md"], nil, %{}, [0, 0], [0.0]]}
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
      |> Map.delete("card_creation")
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

  test "six ordered tasks can cite sixteen snapshot indices while larger sets fail closed" do
    receipt = planning_receipt(Ecto.UUID.generate())
    task = hd(receipt["proposal"]["tasks"])

    tasks =
      for index <- 0..5 do
        Map.merge(task, %{
          "title" => "Task #{index}",
          "depends_on" => Enum.take([0, 1, 2, 3, 4], index),
          "sources" => Enum.to_list(0..15)
        })
      end

    receipt = put_in(receipt, ["proposal", "tasks"], tasks)
    assert Planning.normalize(Jason.encode!(receipt)) == receipt

    for bad <- [
          tasks ++ [Map.put(task, "title", "Seventh")],
          List.replace_at(tasks, 5, Map.put(List.last(tasks), "depends_on", [0, 1, 2, 3, 4, 5])),
          List.replace_at(tasks, 5, Map.put(List.last(tasks), "sources", Enum.to_list(0..16)))
        ] do
      assert Planning.normalize(Jason.encode!(put_in(receipt, ["proposal", "tasks"], bad)))[
               "status"
             ] == "invalid_response"
    end
  end

  test "import failure rolls back linked drafts and source receipts together", %{board: board} do
    claim = document_plan_fixture(board) |> legacy_plan_fixture()
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

  test "automatic graph completion is atomic, durable and retains source receipts", %{
    board: board
  } do
    claim = document_plan_fixture(board)
    receipt = linked_planning_receipt(claim.id)
    assert claim.payload["card_creation"] == "automatic-v1"
    before_events = Repo.all(Event)

    # Fail after the first card and receipt have been written inside the transaction.
    SQL.query!(
      Repo,
      """
      CREATE TEMP TRIGGER reject_second_card BEFORE INSERT ON events
      WHEN NEW.kind = 'planning.task_imported' AND json_extract(NEW.data, '$.index') = 1
      BEGIN SELECT RAISE(ABORT, 'fixture'); END
      """,
      []
    )

    assert_raise Exqlite.Error, fn -> Foundation.finish(claim, receipt) end
    assert Repo.get!(Command, claim.id) == claim
    assert Tabulae.tasks(board.id) == []
    assert Tabulae.imported(board.id) == %{}
    assert Repo.all(Event) == before_events
    SQL.query!(Repo, "DROP TRIGGER reject_second_card", [])

    {:ok, plan} = Foundation.finish(claim, receipt)
    [first, second, third] = for i <- 0..2, do: imported_revision(board, plan.id, i)
    assert first.content["depends_on"] == []
    assert second.content["depends_on"] == [first.task_id]
    assert third.content["depends_on"] == [first.task_id, second.task_id]
    assert Enum.all?(Tabulae.tasks(board.id), &(&1.column == "specs"))
    assert Tabulae.source(board.id, third.task_id).documents == plan.payload["documents"]

    assert Repo.get_by!(Event, command_id: plan.id, kind: "planning.completed").data["task_count"] ==
             3

    receipts = Tabulae.imported(board.id)
    assert {:error, :lost_claim} = Foundation.finish(claim, receipt)
    assert {:ok, nil} = Foundation.claim()
    assert Tabulae.imported(board.id) == receipts
    assert Repo.get!(Command, plan.id) == plan
  end

  test "an expired lease cannot create cards even before reconciliation", %{board: board} do
    {:ok, _} = request(board)
    {:ok, claim} = Foundation.claim(1_000)
    assert {:error, :lost_claim} = Foundation.finish(claim, planning_receipt(claim.id))
    assert Tabulae.tasks(board.id) == []
    assert {:ok, %{result: "interrupted"}} = Foundation.claim()
    assert {:ok, nil} = Foundation.claim()
  end

  test "pre-upgrade consent cannot authorize automatic card creation", %{board: board} do
    payload = Map.delete(Planning.setup(board).payload, "card_creation")
    old_token = Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(payload)))

    assert {:ok, %{state: "rejected", result: "planning_setup_changed"}} =
             request(board, token: old_token)

    assert Tabulae.tasks(board.id) == []
  end
end
