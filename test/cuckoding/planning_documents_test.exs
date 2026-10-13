defmodule Cuckoding.PlanningDocumentsTest do
  use Cuckoding.DataCase
  import Cuckoding.PlanningFixtures
  alias Cuckoding.{Command, Event, Foundation, Planning, PlanningDocuments, Tabulae}
  setup do: planning_fixture()

  defp preview(board, paths \\ ["docs/plan.md"], key \\ Ecto.UUID.generate()),
    do: PlanningDocuments.request(key, board.arena_id, board.id, paths)

  test "scoped snapshots freeze with consent and retain import provenance", %{board: board} do
    revision = Foundation.workspace().revision
    {:ok, command} = preview(board)
    assert {:ok, ^command} = preview(board, ["docs/plan.md"], command.id)
    assert {:error, :key_conflict} = preview(board, ["other.md"], command.id)
    assert {:error, "documents_expired"} = PlanningDocuments.selected(board, command.id)
    {:ok, claim} = Foundation.claim()
    {:ok, saved} = Foundation.finish(claim, document_receipt())
    assert saved.payload["observation"]["elapsed_ms"] == 12
    assert Foundation.workspace().revision == revision
    refute inspect(Repo.all(Event)) =~ "Selected plan"
    refute inspect(Repo.all(Event)) =~ "docs/plan.md"
    assert {:ok, files} = PlanningDocuments.selected(board, command.id)
    {:ok, other} = Tabulae.create(Ecto.UUID.generate(), board.arena_id, "Other")
    assert {:error, "documents_expired"} = PlanningDocuments.selected(other, command.id)
    setup = Planning.setup(board, command.id)
    assert setup.payload["documents"] == files
    refute setup.token == Planning.setup(board).token

    assert {:error, "planning_confirmation_required"} =
             Planning.request(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               "Use selected docs",
               setup.token,
               false,
               command.id
             )

    {:ok, plan} =
      Planning.request(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        "Use selected docs",
        setup.token,
        true,
        command.id
      )

    assert plan.payload["document_preview_id"] == command.id
    assert plan.payload["documents"] == files
    refute plan.payload["path"]
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, planning_receipt(plan.id))

    saved
    |> Ecto.Changeset.change(updated_at: DateTime.add(DateTime.utc_now(), -301))
    |> Repo.update!()

    assert {:error, "documents_expired"} = PlanningDocuments.selected(board, command.id)
    assert Planning.setup(board, command.id).token == nil

    assert {:ok, %{state: "rejected"}} =
             Planning.request(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               "Old docs",
               setup.token,
               true,
               command.id
             )

    draft = imported_revision(board, plan.id)

    assert Repo.get!(Command, draft.command_id).payload["proposal_id"] == plan.id
    assert Repo.get!(Command, plan.id).payload["documents"] == files
  end

  test "selection and returned snapshots fail closed", %{board: board} do
    for paths <- [
          [],
          ["../secret.md"],
          ["/tmp/doc.md"],
          [".env/notes.md"],
          ["file.ex"],
          ["x.md", "x.md"],
          Enum.map(1..5, &"#{&1}.md")
        ] do
      assert {:error, "invalid_documents"} = preview(board, paths)
    end

    for receipt <- [
          document_receipt("other.md"),
          document_receipt("docs/plan.md", "bad\0text"),
          document_receipt("docs/plan.md", String.duplicate("a", 4097)),
          put_in(document_receipt(), ["files", Access.at(0), "sha256"], "forged")
        ] do
      {:ok, command} = preview(board)
      {:ok, claim} = Foundation.claim()
      assert {:ok, %{state: "failed"} = failed} = Foundation.finish(claim, receipt)
      refute failed.payload["observation"]["files"]
      assert {:error, "documents_expired"} = PlanningDocuments.selected(board, command.id)
    end

    bad = put_in(document_receipt(), ["files", Access.at(0), "grant"], "write")
    refute PlanningDocuments.valid_files?(bad["files"])

    files =
      for n <- 1..4, do: hd(document_receipt("#{n}.md", String.duplicate("x", 3001))["files"])

    refute PlanningDocuments.valid_files?(files)
  end

  test "cancelled and expired previews never accept late text or replay reads", %{board: board} do
    {:ok, command} = preview(board)
    {:ok, claim} = Foundation.claim()
    Foundation.cancel_probe(command.id)
    {:ok, %{state: "rejected"}} = preview(board)
    assert PlanningDocuments.latest(board.id).id == command.id
    assert {:ok, %{state: "cancelled"} = saved} = Foundation.finish(claim, document_receipt())
    refute saved.payload["observation"]["files"]
    {:ok, _} = preview(board)
    {:ok, claim} = Foundation.claim(1_000)
    assert {:ok, %{state: "failed", result: "interrupted"}} = Foundation.claim(26_001)
    assert {:ok, nil} = Foundation.claim(26_002)
    assert {:error, :lost_claim} = Foundation.finish(claim, document_receipt())
  end

  test "folder snapshots freeze source policy and 16 citations without live access", %{
    board: board
  } do
    key = Ecto.UUID.generate()
    {:ok, command} = PlanningDocuments.scan(key, board.arena_id, board.id)
    assert {:ok, ^command} = PlanningDocuments.scan(key, board.arena_id, board.id)
    assert {:error, :key_conflict} = preview(board, ["docs/plan.md"], key)
    {:ok, claim} = Foundation.claim()
    {:ok, saved} = Foundation.finish(claim, folder_receipt())
    assert saved.result == "previewed"
    assert {:ok, files} = PlanningDocuments.selected(board, command.id)
    assert length(files) == 16
    setup = Planning.setup(board, command.id)

    assert {:ok, plan} =
             Planning.request(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               "",
               setup.token,
               true,
               command.id
             )

    assert plan.payload["contract"] == "brief-plan-v3"
    assert plan.payload["documents"] == files
    refute plan.payload["path"]
    {:ok, claim} = Foundation.claim()

    receipt =
      put_in(planning_receipt(plan.id), ["proposal", "tasks", Access.at(0), "sources"], [15])

    {:ok, finished} = Foundation.finish(claim, receipt)
    assert finished.state == "completed"
    assert Planning.sources(finished, 0) == [List.last(files)]
    legacy = %{finished | payload: Map.put(finished.payload, "contract", "brief-plan-v2")}
    assert Planning.proposal(legacy) == nil

    assert imported_revision(board, plan.id).content["column"] == "specs"

    refute inspect(Repo.all(Event)) =~ "Selected plan"
    refute inspect(Repo.all(Event)) =~ "docs/15.md"
  end

  test "folder policy does not widen manual selection or accept unsafe and excessive receipts", %{
    board: board
  } do
    for receipt <- [
          folder_receipt([hd(document_receipt(".private/read.md")["files"])]),
          folder_receipt([hd(document_receipt("secrets/plan.md")["files"])]),
          folder_receipt([hd(document_receipt("node_modules/file.js")["files"])]),
          folder_receipt([
            hd(document_receipt("lib/file.ex", String.duplicate("x", 16_385))["files"])
          ]),
          folder_receipt(
            for n <- 1..5,
                do: hd(document_receipt("#{n}.txt", String.duplicate("x", 16_384))["files"])
          ),
          put_in(folder_receipt(), ["scan", "visited"], 2_001),
          put_in(folder_receipt(), ["scan", "skipped"], %{"arbitrary text" => 1}),
          put_in(folder_receipt(), ["files", Access.at(0), "sha256"], "forged")
        ] do
      assert PlanningDocuments.normalize(receipt) == %{"status" => "invalid_documents"}
    end

    {:ok, _} = preview(board)
    {:ok, claim} = Foundation.claim()
    assert {:ok, %{result: "invalid_documents"}} = Foundation.finish(claim, folder_receipt())
    {:ok, _} = PlanningDocuments.scan(Ecto.UUID.generate(), board.arena_id, board.id)
    {:ok, claim} = Foundation.claim()
    assert {:ok, %{result: "invalid_documents"}} = Foundation.finish(claim, document_receipt())
  end

  test "empty scans require a brief and cancelled scans retain no late sources", %{board: board} do
    {:ok, command} = PlanningDocuments.scan(Ecto.UUID.generate(), board.arena_id, board.id)
    {:ok, claim} = Foundation.claim()
    assert {:ok, %{state: "completed"}} = Foundation.finish(claim, folder_receipt([]))
    setup = Planning.setup(board, command.id)

    assert {:error, "planning_confirmation_required"} =
             Planning.request(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               "",
               setup.token,
               true,
               command.id
             )

    assert {:ok, []} = PlanningDocuments.selected(board, command.id)
    {:ok, command} = PlanningDocuments.scan(Ecto.UUID.generate(), board.arena_id, board.id)
    {:ok, claim} = Foundation.claim()
    Foundation.cancel_probe(command.id)
    assert {:ok, %{state: "cancelled"} = saved} = Foundation.finish(claim, folder_receipt())
    refute saved.payload["observation"]["files"]
  end
end
