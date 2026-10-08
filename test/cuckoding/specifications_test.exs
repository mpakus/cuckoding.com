defmodule Cuckoding.SpecificationsTest do
  use Cuckoding.DataCase
  import Cuckoding.SpecificationFixtures
  alias Cuckoding.{Command, DraftTask, Event, Foundation, Specifications, Storage, Tabulae}
  alias Ecto.Adapters.SQL
  setup do: specification_fixture()

  test "acceptance freezes Markdown before writing, then moves the exact task atomically", ctx do
    %{board: board, task: task, attrs: attrs, root: root} = ctx
    {:ok, preview} = Specifications.preview(board.arena_id, board.id, task, 1)
    refute File.exists?(Path.join(root, "specifications"))

    assert {:error, "confirmation_required"} =
             Specifications.request(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               task,
               1,
               preview["sha256"],
               false
             )

    {:ok, command} = request_spec(board, task)
    assert command.payload == preview
    assert {:ok, ^command} = request_spec(board, task, 1, command.id)
    {:ok, claim} = Foundation.claim()
    result = Specifications.execute(claim)
    assert result["status"] == "written"
    assert Repo.get!(DraftTask, task).column == "specs"
    assert {:error, :unavailable} = Specifications.read(command.id)
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    {:ok, done} = Foundation.finish(claim, result)
    assert_receive :updated
    assert done.result == "accepted"
    assert Specifications.current?(done)
    assert {:ok, preview["markdown"]} == Specifications.read(command.id)
    raw_id = command.id |> String.replace("-", "") |> Base.decode16!(case: :lower)
    assert {:error, :unavailable} = Specifications.read(raw_id)
    assert {:error, :unavailable} = Specifications.read(String.upcase(command.id))

    assert File.stat!(Path.join(root, "specifications/#{command.id}.md")).mode
           |> Bitwise.band(0o777) == 0o600

    assert %{revision: 2, column: "todo"} = Repo.get!(DraftTask, task)
    assert hd(Tabulae.history(board.id, task)).command_id == command.id

    assert {:ok, ^done} =
             Specifications.request(
               command.id,
               board.arena_id,
               board.id,
               task,
               1,
               preview["sha256"],
               true
             )

    assert {:error, "already_accepted"} = request_spec(board, task, 2)

    assert {:error, :key_conflict} =
             Specifications.request(
               command.id,
               board.arena_id,
               board.id,
               task,
               1,
               String.duplicate("0", 64),
               true
             )

    assert {:error, :lost_claim} = Foundation.finish(claim, result)
    refute inspect(Repo.all(Event)) =~ attrs["description"]

    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        task,
        2,
        Map.put(attrs, "title", "Revised")
      )

    refute Specifications.current?(done)
    assert {:ok, preview["markdown"]} == Specifications.read(command.id)
    assert Foundation.workspace().revision == 0
  end

  test "scope, readiness, changed dependencies and forged hash cannot accept a different preview",
       %{board: b, task: task, attrs: attrs} do
    for {arena, board, id, revision} <- [
          {Ecto.UUID.generate(), b.id, task, 1},
          {b.arena_id, Ecto.UUID.generate(), task, 1},
          {b.arena_id, b.id, Ecto.UUID.generate(), 1},
          {b.arena_id, b.id, %{}, 1}
        ] do
      assert {:error, "scope_missing"} = Specifications.preview(arena, board, id, revision)
    end

    assert {:error, "stale_task"} = Specifications.preview(b.arena_id, b.id, task, 2)

    assert {:error, "preview_changed"} =
             Specifications.request(
               Ecto.UUID.generate(),
               b.arena_id,
               b.id,
               task,
               1,
               String.duplicate("0", 64),
               true
             )

    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        b.arena_id,
        b.id,
        task,
        1,
        Map.put(attrs, "criteria", "")
      )

    assert {:error, "criteria_required"} = Specifications.preview(b.arena_id, b.id, task, 2)
    dependency = Ecto.UUID.generate()
    {:ok, _} = Tabulae.save(Ecto.UUID.generate(), b.arena_id, b.id, dependency, 0, attrs)

    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        b.arena_id,
        b.id,
        task,
        2,
        Map.put(attrs, "depends_on", [dependency])
      )

    {:ok, preview} = Specifications.preview(b.arena_id, b.id, task, 3)
    {:ok, _} = request_spec(b, task, 3)
    {:ok, claim} = Foundation.claim()
    result = Specifications.execute(claim)
    {:ok, _} = Tabulae.save(Ecto.UUID.generate(), b.arena_id, b.id, dependency, 1, attrs)
    refute Specifications.unchanged?(preview)
    {:ok, done} = Foundation.finish(claim, result)
    assert done.result == "preview_changed"
    assert Repo.get!(DraftTask, task).revision == 3
    assert {:error, :unavailable} = Specifications.read(claim.id)
  end

  test "cancelled, expired and event-failed writes retain artifacts without accepting or replaying",
       %{board: b, task: task, root: root} do
    {:ok, _} = request_spec(b, task)
    {:ok, claim} = Foundation.claim()
    result = Specifications.execute(claim)
    Foundation.cancel_probe(claim.id)
    {:ok, cancelled} = Foundation.finish(claim, result)
    assert cancelled.state == "cancelled"
    assert File.exists?(Path.join(root, "specifications/#{claim.id}.md"))
    {:ok, _} = request_spec(b, task)
    {:ok, claim} = Foundation.claim()
    result = Specifications.execute(claim)
    Repo.update!(Ecto.Changeset.change(claim, lease_until: 0))
    {:ok, interrupted} = Foundation.claim()
    assert interrupted.result == "interrupted"
    assert {:error, :lost_claim} = Foundation.finish(claim, result)
    assert {:ok, nil} = Foundation.claim()
    {:ok, _} = request_spec(b, task)
    {:ok, claim} = Foundation.claim()
    result = Specifications.execute(claim)

    SQL.query!(
      Repo,
      "CREATE TEMP TRIGGER reject_spec_event BEFORE INSERT ON events WHEN NEW.kind = 'spec.completed' BEGIN SELECT RAISE(ABORT, 'fixture failure'); END",
      []
    )

    assert_raise Exqlite.Error, fn -> Foundation.finish(claim, result) end
    assert %{revision: 1, column: "specs"} = Repo.get!(DraftTask, task)
    assert length(Tabulae.history(b.id, task)) == 1
    assert Repo.get!(Command, claim.id).state == "running"
    assert File.exists?(Path.join(root, "specifications/#{claim.id}.md"))
    SQL.query!(Repo, "DROP TRIGGER reject_spec_event", [])
  end

  test "artifacts reject overwrite, traversal, symlinks, hardlinks, oversized and modified bytes",
       %{board: b, task: task, root: root} do
    {:ok, _} = request_spec(b, task)
    {:ok, claim} = Foundation.claim()
    {:ok, done} = Foundation.finish(claim, Specifications.execute(claim))
    path = Path.join(root, "specifications/#{claim.id}.md")
    assert {:error, :unavailable} = Storage.write_spec(claim.id, "overwrite")
    assert {:error, :unavailable} = Storage.write_spec("../escape", "text")

    assert {:error, :unavailable} =
             Storage.write_spec(Ecto.UUID.generate(), String.duplicate("a", 262_145))

    File.write!(path, "edited locally")
    assert {:error, :unavailable} = Specifications.read(done.id)
    assert {:ok, _} = request_spec(b, task, 2)
    File.rm!(path)
    target = Path.join(root, "keep.txt")
    File.write!(target, "private-canary")
    File.ln_s!(target, path)
    assert {:error, :unavailable} = Specifications.read(done.id)
    assert {:error, :unavailable} = Storage.write_spec(done.id, "overwrite")
    assert File.read!(target) == "private-canary"
    File.rm!(path)
    File.ln!(target, path)
    assert {:error, :unavailable} = Specifications.read(done.id)
    File.rm!(path)
    File.mkdir!(path)
    assert {:error, :unavailable} = Specifications.read(done.id)
  end

  test "imported citations and Markdown control text remain literal in the accepted snapshot" do
    ctx = Cuckoding.PlanningFixtures.planning_fixture()
    claim = Cuckoding.PlanningFixtures.document_plan_fixture(ctx.board)

    {:ok, _} =
      Foundation.finish(claim, Cuckoding.PlanningFixtures.linked_planning_receipt(claim.id))

    {:ok, first} =
      Tabulae.import_proposal(Ecto.UUID.generate(), ctx.board.arena_id, ctx.board.id, claim.id, 0)

    task = hd(Tabulae.tasks(ctx.board.id))

    content =
      Map.put(
        Tabulae.content(task),
        "description",
        "```\n<script>alert('literal')</script>\n````"
      )

    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        ctx.board.arena_id,
        ctx.board.id,
        first.task_id,
        1,
        content
      )

    {:ok, p} = Specifications.preview(ctx.board.arena_id, ctx.board.id, first.task_id, 2)
    assert p["markdown"] =~ "`````text\n```\n<script>"
    assert p["markdown"] =~ "Build a small feature."
    assert p["source"] == %{"plan_id" => claim.id, "index" => 0}
    assert p["documents"] == claim.payload["documents"]
  end
end
