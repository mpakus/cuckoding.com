defmodule Cuckoding.WorkflowsTest do
  use Cuckoding.DataCase
  import Cuckoding.BattleFixtures
  alias Cuckoding.{Battles, Command, Tabula, Tabulae, Workflows}

  setup do
    fixture()
  end

  defp names(board), do: Workflows.labels(board.definition)

  test "scoped label revisions preserve the original board and stable command replay", ctx do
    original = Repo.get!(Tabula, ctx.board.id)
    base = Workflows.current(original)
    assert base.revision == 0 and base.definition == original.definition
    renamed = Map.merge(names(original), %{"specs" => "Discovery", "in_process" => "Build"})
    key = Ecto.UUID.generate()
    {:ok, saved} = Workflows.save_labels(key, original.arena_id, original.id, 0, renamed)
    assert saved.revision == 1
    assert Repo.get!(Tabula, original.id) == original
    projected = Tabulae.get(original.arena_id, original.id)
    assert projected.workflow_revision == 1
    assert Workflows.labels(projected.definition) == renamed

    assert Enum.map(projected.definition["columns"], &Map.take(&1, ~w(key role))) ==
             Enum.map(original.definition["columns"], &Map.take(&1, ~w(key role)))

    next_names = Map.put(renamed, "review", "Independent review")

    {:ok, later} =
      Workflows.save_labels(Ecto.UUID.generate(), original.arena_id, original.id, 1, next_names)

    assert later.revision == 2
    count = Repo.aggregate(Cuckoding.Event, :count)
    assert {:ok, ^saved} = Workflows.save_labels(key, original.arena_id, original.id, 0, renamed)
    assert Repo.aggregate(Cuckoding.Event, :count) == count

    assert {:error, :key_conflict} =
             Workflows.save_labels(key, original.arena_id, original.id, 0, next_names)

    assert length(Workflows.history(original.id)) == 2
    {:ok, sibling} = Tabulae.create(Ecto.UUID.generate(), original.arena_id, "Sibling")
    assert Workflows.current(sibling).revision == 0
    assert Workflows.labels(sibling.definition) == names(original)
  end

  test "labels cannot alter keys roles order or scope and malformed names never write", ctx do
    labels = names(ctx.board)
    before = Repo.aggregate(Command, :count)

    for invalid <- [
          Map.delete(labels, "review"),
          Map.put(labels, "extra", "Role"),
          Map.put(labels, "specs", %{"role" => "implementor"}),
          Map.put(labels, "specs", " "),
          Map.put(labels, "specs", "bad\nname"),
          Map.put(labels, "specs", String.duplicate("x", 41)),
          Map.put(labels, "review", "  specs  ")
        ] do
      assert {:error, "invalid_workflow"} =
               Workflows.save_labels(
                 Ecto.UUID.generate(),
                 ctx.board.arena_id,
                 ctx.board.id,
                 0,
                 invalid
               )
    end

    assert Repo.aggregate(Command, :count) == before
    other = Cuckoding.DataCase.arena_fixture()
    renamed = Map.put(labels, "specs", "Discovery")

    assert {:error, "scope_missing"} =
             Workflows.save_labels(Ecto.UUID.generate(), other.id, ctx.board.id, 0, renamed)

    assert {:error, "stale_workflow"} =
             Workflows.save_labels(
               Ecto.UUID.generate(),
               ctx.board.arena_id,
               ctx.board.id,
               9,
               renamed
             )

    assert {:error, "workflow_unchanged"} =
             Workflows.save_labels(
               Ecto.UUID.generate(),
               ctx.board.arena_id,
               ctx.board.id,
               0,
               labels
             )

    assert Workflows.current(ctx.board).revision == 0
  end

  test "active planning or battle refuses edits and Starts freeze the selected workflow", ctx do
    labels = Map.put(names(ctx.board), "review", "Judge")

    planning =
      Repo.insert!(%Command{
        id: Ecto.UUID.generate(),
        kind: "plan_tabula",
        state: "running",
        expected_revision: 0,
        payload: %{"arena_id" => ctx.board.arena_id, "tabula_id" => ctx.board.id}
      })

    assert {:error, "planning_active"} =
             Workflows.save_labels(
               Ecto.UUID.generate(),
               ctx.board.arena_id,
               ctx.board.id,
               0,
               labels
             )

    Repo.update!(Ecto.Changeset.change(planning, state: "cancelled"))
    battle = start(ctx.board)
    assert battle.snapshot["workflow_revision"] == 0
    assert battle.snapshot["workflow_definition"] == ctx.board.definition

    assert {:error, "battle_active"} =
             Workflows.save_labels(
               Ecto.UUID.generate(),
               ctx.board.arena_id,
               ctx.board.id,
               0,
               labels
             )

    {:ok, _} = Battles.stop(battle.id)

    {:ok, _} =
      Workflows.save_labels(Ecto.UUID.generate(), ctx.board.arena_id, ctx.board.id, 0, labels)

    next = start(ctx.board)
    assert next.snapshot["workflow_revision"] == 1
    assert Workflows.labels(next.snapshot["workflow_definition"]) == labels
    assert Battles.get(battle.id).snapshot == battle.snapshot
    assert length(next.snapshot["team"]) == 4
  end

  test "competing saves keep one immutable revision and bounded history", ctx do
    replies =
      1..4
      |> Task.async_stream(fn n ->
        Workflows.save_labels(
          Ecto.UUID.generate(),
          ctx.board.arena_id,
          ctx.board.id,
          0,
          Map.put(names(ctx.board), "specs", "Discovery #{n}")
        )
      end)
      |> Enum.map(fn {:ok, reply} -> reply end)

    assert Enum.count(replies, &match?({:ok, _}, &1)) == 1
    assert Enum.count(replies, &(&1 == {:error, "stale_workflow"})) == 3
    revision = Workflows.current(ctx.board)

    assert_raise Exqlite.Error, fn ->
      Repo.query!("UPDATE workflow_revisions SET revision = 99 WHERE id = ?", [revision.id])
    end

    assert_raise Exqlite.Error, fn ->
      Repo.query!("DELETE FROM workflow_revisions WHERE id = ?", [revision.id])
    end

    for n <- 2..7 do
      {:ok, _} =
        Workflows.save_labels(
          Ecto.UUID.generate(),
          ctx.board.arena_id,
          ctx.board.id,
          n - 1,
          Map.put(names(ctx.board), "specs", "Revision #{n}")
        )
    end

    assert Enum.map(Workflows.history(ctx.board.id), & &1.revision) == [7, 6, 5, 4, 3]
  end

  test "an event failure rolls back both the revision and command", ctx do
    Repo.query!(
      "CREATE TEMP TRIGGER reject_workflow_event BEFORE INSERT ON events WHEN NEW.kind = 'workflow.completed' BEGIN SELECT RAISE(ABORT, 'fixture failure'); END"
    )

    key = Ecto.UUID.generate()

    try do
      assert_raise Exqlite.Error, fn ->
        Workflows.save_labels(
          key,
          ctx.board.arena_id,
          ctx.board.id,
          0,
          Map.put(names(ctx.board), "specs", "Discovery")
        )
      end

      assert Repo.get(Command, key) == nil
      assert Workflows.current(ctx.board).revision == 0
      assert Workflows.history(ctx.board.id) == []
    after
      Repo.query!("DROP TRIGGER reject_workflow_event")
    end
  end
end
