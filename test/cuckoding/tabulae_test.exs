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

  test "prerequisites retain history, preserve legacy saves and clear explicitly", %{board: board} do
    prerequisite = new_task(board)
    id = Ecto.UUID.generate()
    key = Ecto.UUID.generate()
    attrs = Map.put(content(), "depends_on", [prerequisite])
    assert {:ok, first} = Tabulae.save(key, board.arena_id, board.id, id, 0, attrs)
    assert {:ok, ^first} = Tabulae.save(key, board.arena_id, board.id, id, 0, attrs)
    assert first.content["depends_on"] == [prerequisite]
    assert {:ok, second} = save_dependencies(board, id, 1, :omitted)
    assert second.content["depends_on"] == [prerequisite]
    task = Enum.find(Tabulae.tasks(board.id), &(&1.id == id))
    assert Tabulae.content(task)["depends_on"] == [prerequisite]
    assert {:ok, third} = save_dependencies(board, id, 2, [])
    assert third.content["depends_on"] == []
    assert {:ok, ^first} = Tabulae.save(key, board.arena_id, board.id, id, 0, attrs)

    assert Enum.map(Tabulae.history(board.id, id), & &1.content["depends_on"]) ==
             [[], [prerequisite], [prerequisite]]

    assert Repo.get_by!(Event, command_id: first.command_id).data["depends_on"] == [prerequisite]
    assert Repo.get!(DraftTask, id).revision == 3
    assert {:ok, nil} = Foundation.claim()
  end

  test "cycles are checked against the latest graph even when this task is unchanged", %{
    board: board
  } do
    a = new_task(board)
    b = new_task(board)
    c = new_task(board)
    d = new_task(board)
    assert {:ok, _} = save_dependencies(board, b, 1, [a])
    assert {:ok, _} = save_dependencies(board, c, 1, [a])
    assert {:ok, _} = save_dependencies(board, d, 1, [b, c])

    for dependencies <- [[b], [c], [d]] do
      assert {:error, "dependency_cycle"} = save_dependencies(board, a, 1, dependencies)
    end

    assert {:error, "stale_task"} = save_dependencies(board, d, 1, [])
    assert Repo.get!(DraftTask, a).revision == 1
    assert length(Tabulae.history(board.id, a)) == 1
    key = Ecto.UUID.generate()
    attrs = Map.put(content(), "depends_on", [d])
    assert {:error, "dependency_cycle"} = Tabulae.save(key, board.arena_id, board.id, a, 1, attrs)
    assert {:ok, _} = save_dependencies(board, d, 2, [])
    assert {:error, "dependency_cycle"} = Tabulae.save(key, board.arena_id, board.id, a, 1, attrs)
    assert {:ok, _} = save_dependencies(board, a, 1, [d])
  end

  test "prerequisites are bounded, distinct canonical IDs of other tasks on this board", %{
    board: board
  } do
    id = new_task(board)
    ids = Enum.map(1..17, fn _ -> new_task(board) end)
    {:ok, sibling} = Tabulae.create(Ecto.UUID.generate(), board.arena_id, "Sibling")
    other = arena_fixture()
    {:ok, foreign} = Tabulae.create(Ecto.UUID.generate(), other.id, "Foreign")

    for ref <- [id, Ecto.UUID.generate(), new_task(sibling), new_task(foreign)] do
      assert {:error, "invalid_dependencies"} = save_dependencies(board, id, 1, [ref])
    end

    for invalid <- [
          nil,
          %{},
          "",
          [nil],
          [1],
          [%{}],
          ["bad"],
          [String.upcase(hd(ids))],
          [hd(ids), hd(ids)],
          ids
        ] do
      assert {:error, "invalid_task"} = save_dependencies(board, id, 1, invalid)
    end

    assert {:ok, saved} = save_dependencies(board, id, 1, Enum.take(ids, 16))
    assert length(saved.content["depends_on"]) == 16
  end

  test "pre-prerequisite revisions and command receipts remain byte-for-byte unchanged", %{
    board: board
  } do
    id = Ecto.UUID.generate()
    key = Ecto.UUID.generate()

    payload = %{
      "arena_id" => board.arena_id,
      "tabula_id" => board.id,
      "task_id" => id,
      "content" => content()
    }

    command =
      Repo.insert!(%Command{
        id: key,
        kind: "save_draft",
        state: "completed",
        expected_revision: 0,
        payload: payload
      })

    Repo.insert!(%DraftTask{
      id: id,
      tabula_id: board.id,
      revision: 1,
      title: "A task",
      description: "",
      criteria: "",
      column: "specs"
    })

    revision =
      Repo.insert!(%DraftTaskRevision{
        task_id: id,
        command_id: key,
        revision: 1,
        content: content(),
        inserted_at: DateTime.utc_now()
      })

    assert hd(Tabulae.tasks(board.id)).depends_on == []
    assert {:ok, ^revision} = Tabulae.save(key, board.arena_id, board.id, id, 0, content())
    dependency = new_task(board)
    assert {:ok, _} = save_dependencies(board, id, 1, [dependency])
    assert Repo.get!(Command, key) == command
    assert Repo.get!(DraftTaskRevision, revision.id) == revision
  end

  test "dependency edits roll back with their audit event and never broadcast partial state", %{
    board: board
  } do
    a = new_task(board)
    b = new_task(board)
    before = Tabulae.tasks(board.id)
    revisions = Repo.all(DraftTaskRevision)

    SQL.query!(
      Repo,
      "CREATE TEMP TRIGGER reject_dependency_event BEFORE INSERT ON events WHEN NEW.kind = 'draft.saved' BEGIN SELECT RAISE(ABORT, 'fixture failure'); END",
      []
    )

    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    key = Ecto.UUID.generate()

    assert_raise Exqlite.Error, fn ->
      Tabulae.save(key, board.arena_id, board.id, b, 1, Map.put(content(), "depends_on", [a]))
    end

    assert Tabulae.tasks(board.id) == before
    assert Repo.all(DraftTaskRevision) == revisions
    assert Repo.get(Command, key) == nil
    refute_receive :updated
    SQL.query!(Repo, "DROP TRIGGER reject_dependency_event", [])
  end

  defp new_task(board) do
    id = Ecto.UUID.generate()
    assert {:ok, _} = save_dependencies(board, id, 0, [])
    id
  end

  defp save_dependencies(board, id, revision, dependencies) do
    attrs =
      if dependencies == :omitted,
        do: content(),
        else: Map.put(content(), "depends_on", dependencies)

    Tabulae.save(Ecto.UUID.generate(), board.arena_id, board.id, id, revision, attrs)
  end

  defp content,
    do: %{"title" => "A task", "description" => "", "criteria" => "", "column" => "specs"}
end
