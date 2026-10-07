defmodule Cuckoding.TabulaeTest do
  use Cuckoding.DataCase
  alias Ecto.Adapters.SQL

  alias Cuckoding.{
    Command,
    DraftTask,
    DraftTaskRevision,
    Event,
    Foundation,
    Tabula,
    Tabulae,
    Team
  }

  import Cuckoding.DataCase, only: [arena_fixture: 0]

  setup do
    arena = arena_fixture()
    {:ok, board} = Tabulae.create(Ecto.UUID.generate(), arena.id, "First battle")
    %{arena: arena, board: board}
  end

  test "boards inherit the Arena team, retain workflow identity and create no execution", %{
    arena: arena,
    board: board
  } do
    roles = put_in(Team.editable(Team.current()), [Access.at(0), "name"], "New planner")
    assert {:ok, _} = Team.save(Ecto.UUID.generate(), 1, roles)
    key = Ecto.UUID.generate()
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    assert {:ok, second} = Tabulae.create(key, arena.id, "Next battle")
    assert_receive :updated
    assert {:ok, ^second} = Tabulae.create(key, arena.id, "Next battle")
    assert {:error, :key_conflict} = Tabulae.create(key, arena.id, "Changed")
    assert second.team_revision_id == board.team_revision_id
    assert second.team_revision_id == 1

    assert Tabulae.get(arena.id, second.id).team_revision.definition["roles"]
           |> hd()
           |> Map.get("name") == "Speculator"

    assert second.definition["execution"] == "disabled"

    assert Enum.map(second.definition["columns"], & &1["key"]) ==
             ~w(specs todo in_process review completed)

    assert length(Tabulae.list(arena.id)) == 2
    assert Foundation.workspace().revision == 0
    assert {:ok, nil} = Foundation.claim()
    refute File.exists?(arena.path)
    assert Repo.aggregate(Tabula, :count) == 2
  end

  test "tasks save and move with immutable history and original idempotent receipts", %{
    arena: arena,
    board: board
  } do
    id = Ecto.UUID.generate()
    key = Ecto.UUID.generate()
    attrs = content()
    assert {:ok, first} = Tabulae.save(key, arena.id, board.id, id, 0, attrs)
    assert {:ok, ^first} = Tabulae.save(key, arena.id, board.id, id, 0, attrs)

    assert {:error, :key_conflict} =
             Tabulae.save(key, arena.id, board.id, id, 0, %{attrs | "title" => "Different"})

    todo = %{
      attrs
      | "column" => "todo",
        "description" => "Public spec canary",
        "criteria" => "Focused check passes"
    }

    assert {:ok, second} = Tabulae.save(Ecto.UUID.generate(), arena.id, board.id, id, 1, todo)
    assert second.revision == 2
    assert hd(Tabulae.tasks(board.id)).column == "todo"
    assert {:ok, ^first} = Tabulae.save(key, arena.id, board.id, id, 0, attrs)
    assert hd(Tabulae.tasks(board.id)).column == "todo"
    assert {:ok, _} = Tabulae.save(Ecto.UUID.generate(), arena.id, board.id, id, 2, attrs)
    assert Enum.map(Tabulae.history(board.id, id), & &1.revision) == [3, 2, 1]
    assert Repo.aggregate(DraftTask, :count) == 1
    refute inspect(Repo.all(Event)) =~ "Public spec canary"
    assert Repo.get!(DraftTask, id).column == "specs"
    assert {:ok, nil} = Foundation.claim()
    assert Foundation.workspace().revision == 0
  end

  test "stale and foreign edits cannot overwrite a draft", %{arena: arena, board: board} do
    id = Ecto.UUID.generate()
    assert {:ok, _} = Tabulae.save(Ecto.UUID.generate(), arena.id, board.id, id, 0, content())
    key = Ecto.UUID.generate()
    assert {:error, "stale_task"} = Tabulae.save(key, arena.id, board.id, id, 0, content())
    assert {:error, "stale_task"} = Tabulae.save(key, arena.id, board.id, id, 0, content())
    other = arena_fixture()
    {:ok, second} = Tabulae.create(Ecto.UUID.generate(), other.id, "Other")

    for {arena_id, board_id} <- [
          {other.id, board.id},
          {arena.id, second.id},
          {other.id, second.id}
        ] do
      assert {:error, "scope_missing"} =
               Tabulae.save(Ecto.UUID.generate(), arena_id, board_id, id, 1, content())
    end

    assert Tabulae.get(other.id, board.id) == nil
    assert Tabulae.history(second.id, id) == []
    assert Repo.get!(DraftTask, id).revision == 1
    assert Repo.aggregate(DraftTaskRevision, :count) == 1
    assert Repo.get!(Command, key).state == "rejected"
  end

  test "readiness and closed-stage checks apply at the domain boundary", %{
    arena: arena,
    board: board
  } do
    for {column, reason} <- [
          {"todo", "criteria_required"},
          {"in_process", "stage_unavailable"},
          {"review", "stage_unavailable"},
          {"completed", "stage_unavailable"}
        ] do
      assert {:error, ^reason} =
               Tabulae.save(Ecto.UUID.generate(), arena.id, board.id, Ecto.UUID.generate(), 0, %{
                 content()
                 | "column" => column
               })
    end

    assert Repo.aggregate(DraftTask, :count) == 0
    assert Repo.aggregate(DraftTaskRevision, :count) == 0
    assert {:ok, nil} = Foundation.claim()
  end

  test "malformed input is bounded and missing scopes are closed", %{arena: arena, board: board} do
    for bad <- [nil, %{}, "", "\nboard", String.duplicate("a", 81)] do
      assert {:error, "invalid_board"} = Tabulae.create(Ecto.UUID.generate(), arena.id, bad)
    end

    for bad <- [
          %{},
          %{content() | "title" => %{}},
          %{content() | "title" => "\u0000"},
          %{content() | "description" => String.duplicate("a", 8001)},
          Map.put(content(), "grant", "write")
        ] do
      assert {:error, "invalid_task"} =
               Tabulae.save(
                 Ecto.UUID.generate(),
                 arena.id,
                 board.id,
                 Ecto.UUID.generate(),
                 0,
                 bad
               )
    end

    assert {:error, "scope_missing"} =
             Tabulae.create(Ecto.UUID.generate(), Ecto.UUID.generate(), "Missing")

    assert Tabulae.arena("invalid") == nil
    assert Tabulae.get(arena.id, "invalid") == nil
  end

  test "SQLite rejects history rewrites and delivery stages", %{arena: arena, board: board} do
    id = Ecto.UUID.generate()
    {:ok, _} = Tabulae.save(Ecto.UUID.generate(), arena.id, board.id, id, 0, content())

    for sql <- [
          "UPDATE tabulae SET name = 'rewritten'",
          "DELETE FROM tabulae",
          "UPDATE draft_task_revisions SET revision = 9",
          "DELETE FROM draft_task_revisions",
          "UPDATE draft_tasks SET column = 'completed'"
        ] do
      assert {:error, _} = SQL.query(Repo, sql, [])
    end

    assert Repo.get!(DraftTask, id).column == "specs"
  end

  test "event failure rolls back the whole mutation", %{arena: arena, board: board} do
    SQL.query!(
      Repo,
      "CREATE TEMP TRIGGER reject_draft_event BEFORE INSERT ON events WHEN NEW.kind = 'draft.saved' BEGIN SELECT RAISE(ABORT, 'fixture failure'); END",
      []
    )

    key = Ecto.UUID.generate()

    assert_raise Exqlite.Error, fn ->
      Tabulae.save(key, arena.id, board.id, Ecto.UUID.generate(), 0, content())
    end

    assert Repo.get(Command, key) == nil
    assert Tabulae.tasks(board.id) == []
    assert Repo.aggregate(DraftTaskRevision, :count) == 0
    SQL.query!(Repo, "DROP TRIGGER reject_draft_event", [])
  end

  defp content,
    do: %{"title" => "A task", "description" => "", "criteria" => "", "column" => "specs"}
end
