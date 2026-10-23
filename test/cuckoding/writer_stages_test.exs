defmodule Cuckoding.WriterStagesTest do
  use Cuckoding.DataCase
  import Cuckoding.BattleFixtures
  alias Cuckoding.{Battles, Team, TeamAssignments, Workflows}
  alias Cuckoding.Battles.Stages

  setup do
    ctx = fixture()
    old = TeamAssignments.assigned(ctx.board)

    roles =
      for name <- ["Prepare fixtures", "Polish", "Audit"],
          do:
            Team.custom_role()
            |> Map.merge(%{"name" => name, "agent" => "codex", "model_id" => "test-id"})

    {:ok, team} =
      Team.save(Ecto.UUID.generate(), old.id, Team.editable(old) ++ roles, false, ctx.board)

    steps =
      Enum.zip(roles, [{"write", "before"}, {"write", "after"}, {"read", "after"}])
      |> Enum.map(fn {role, {access, position}} ->
        %{
          "key" => "step_" <> Ecto.UUID.generate(),
          "name" => role["name"],
          "role" => role["id"],
          "access" => access,
          "position" => position
        }
      end)

    Map.merge(ctx, %{team: team, steps: steps})
  end

  test "new workflow freezes explicit grants and captures each writer before continuing", ctx do
    key = Ecto.UUID.generate()
    labels = Workflows.labels(ctx.board.definition)

    {:ok, revision} =
      Workflows.configure_execution(
        key,
        ctx.board.arena_id,
        ctx.board.id,
        0,
        ctx.team.id,
        labels,
        ctx.steps
      )

    assert {:ok, ^revision} =
             Workflows.configure_execution(
               key,
               ctx.board.arena_id,
               ctx.board.id,
               0,
               ctx.team.id,
               labels,
               ctx.steps
             )

    battle = start(ctx.board)
    assert battle.snapshot["custom_stages"] == Stages.writer_policy()
    [before, after_writer, reader] = ctx.steps
    snapshot = battle.snapshot
    assert Stages.next(snapshot, "speculator") == before["key"]
    assert Stages.access(snapshot, before["key"]) == "write"
    assert Stages.next(snapshot, before["key"]) == "capture"
    assert Stages.next(snapshot, "capture", %{"writer_stage" => before["key"]}) == "implementor"

    assert Stages.next(snapshot, "capture", %{"writer_stage" => "implementor"}) ==
             after_writer["key"]

    assert Stages.next(snapshot, "capture", %{"writer_stage" => after_writer["key"]}) ==
             reader["key"]

    assert Stages.next(snapshot, reader["key"]) == "checks"

    assert Stages.access(Map.put(snapshot, "custom_stages", Stages.policy()), before["key"]) ==
             "read"

    assert Stages.custom(Map.put(snapshot, "custom_stages", Stages.policy())) == []

    assert {:error, "unsupported_workflow"} =
             Workflows.configure(
               Ecto.UUID.generate(),
               ctx.board.arena_id,
               ctx.board.id,
               1,
               ctx.team.id,
               labels,
               []
             )

    {:ok, _} = Battles.stop(battle.id)
  end

  test "invalid grants and foreign roles do not become writer authority", ctx do
    [step | _] = ctx.steps
    labels = Workflows.labels(ctx.board.definition)

    for bad <- [
          Map.put(step, "access", "shell"),
          Map.delete(step, "access"),
          Map.put(step, "position", "after_review"),
          Map.put(step, "grant", "write")
        ] do
      assert {:error, "invalid_workflow"} =
               Workflows.configure_execution(
                 Ecto.UUID.generate(),
                 ctx.board.arena_id,
                 ctx.board.id,
                 0,
                 ctx.team.id,
                 labels,
                 [bad]
               )
    end

    assert {:error, "stale_team"} =
             Workflows.configure_execution(
               Ecto.UUID.generate(),
               ctx.board.arena_id,
               ctx.board.id,
               0,
               ctx.team.id,
               labels,
               [Map.put(step, "role", Ecto.UUID.generate())]
             )

    assert Workflows.current(ctx.board).revision == 0
  end
end
