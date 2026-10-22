defmodule Cuckoding.CustomStagesTest do
  use Cuckoding.DataCase
  import Cuckoding.BattleFixtures
  alias Cuckoding.{Battles, Team, TeamAssignments, Workflows}
  alias Cuckoding.Battles.Stages

  setup do
    ctx = fixture()
    old = TeamAssignments.assigned(ctx.board)

    roles =
      for name <- ["Research", "Risk check"],
          do:
            Team.custom_role()
            |> Map.merge(%{"name" => name, "agent" => "codex", "model_id" => "test-id"})

    {:ok, team} =
      Team.save(Ecto.UUID.generate(), old.id, Team.editable(old) ++ roles, false, ctx.board)

    steps =
      Enum.map(
        roles,
        &%{"key" => "step_" <> Ecto.UUID.generate(), "name" => &1["name"], "role" => &1["id"]}
      )

    Map.merge(ctx, %{team: team, steps: steps})
  end

  test "selected roles execute in order and independent review still gates completion", ctx do
    {:ok, revision} =
      Workflows.configure(
        Ecto.UUID.generate(),
        ctx.board.arena_id,
        ctx.board.id,
        0,
        ctx.team.id,
        Workflows.labels(ctx.board.definition),
        ctx.steps
      )

    battle = start(ctx.board)
    assert battle.snapshot["workflow_revision"] == revision.revision
    assert battle.snapshot["custom_stages"] == Stages.policy()

    assert Enum.map(Enum.drop(battle.snapshot["team"], 4), & &1["id"]) ==
             Enum.map(ctx.steps, & &1["role"])

    assert {:ok, preview} = Battles.preview(ctx.board.arena_id, ctx.board.id)
    assert preview.planning_roles == []

    stages =
      Enum.reduce_while(1..80, [], fn _, history ->
        case Battles.claim_next(battle.id) do
          {:ok, attempt} ->
            if Stages.custom_key?(attempt.stage) do
              assert attempt.role == Stages.role(battle.snapshot, attempt.stage)
              assert result(attempt)["provider"]["access"] == "read"

              assert {:error, :invalid_result} =
                       Battles.finish(
                         attempt.id,
                         attempt.claim_token,
                         put_in(result(attempt), ["provider", "access"], "write")
                       )
            end

            if Stages.custom_key?(attempt.stage) do
              edited =
                update_in(result(attempt), ["provider", "tools"], fn [tool] ->
                  [%{tool | "tool" => "edit_file"}]
                end)

              assert {:error, :invalid_result} =
                       Battles.finish(attempt.id, attempt.claim_token, edited)

              assert {:error, :invalid_result} =
                       Battles.finish(
                         attempt.id,
                         attempt.claim_token,
                         put_in(
                           result(attempt),
                           ["provider", "report", "summary"],
                           String.duplicate("x", 513)
                         )
                       )
            end

            {:ok, _} = Battles.finish(attempt.id, attempt.claim_token, result(attempt))
            {:cont, history ++ [attempt.stage]}

          {:error, :not_running} ->
            {:halt, history}
        end
      end)

    assert Battles.get(battle.id).state == "completed"
    expected = ["speculator"] ++ Enum.map(ctx.steps, & &1["key"]) ++ ["implementor"]
    assert Enum.any?(Enum.chunk_every(stages, length(expected), 1, :discard), &(&1 == expected))
    assert Enum.count(stages, &(&1 == "secutor")) == 2
    assert Enum.count(stages, &(&1 == "final_secutor")) == 1
  end

  test "configuration refuses foreign roles, stale teams and accidental stage removal", ctx do
    names = Workflows.labels(ctx.board.definition)
    [step | _] = ctx.steps

    assert {:error, "stale_team"} =
             Workflows.configure(
               Ecto.UUID.generate(),
               ctx.board.arena_id,
               ctx.board.id,
               0,
               ctx.team.id - 1,
               names,
               ctx.steps
             )

    assert {:error, "stale_team"} =
             Workflows.configure(
               Ecto.UUID.generate(),
               ctx.board.arena_id,
               ctx.board.id,
               0,
               ctx.team.id,
               names,
               [%{step | "role" => Ecto.UUID.generate()}]
             )

    assert {:error, "invalid_workflow"} =
             Workflows.configure(
               Ecto.UUID.generate(),
               ctx.board.arena_id,
               ctx.board.id,
               0,
               ctx.team.id,
               names,
               [step, step]
             )

    {:ok, _} =
      Workflows.configure(
        Ecto.UUID.generate(),
        ctx.board.arena_id,
        ctx.board.id,
        0,
        ctx.team.id,
        names,
        ctx.steps
      )

    assert {:error, "unsupported_workflow"} =
             Workflows.save_labels(
               Ecto.UUID.generate(),
               ctx.board.arena_id,
               ctx.board.id,
               1,
               Map.put(names, "specs", "Brief")
             )

    assert length(Workflows.read_stages(Workflows.current(ctx.board).definition)) == 2

    assert Stages.custom(%{"workflow_definition" => Workflows.current(ctx.board).definition}) ==
             []
  end

  test "custom stages retain pause retry budgets and historical stage order", ctx do
    {:ok, _} =
      Workflows.configure(
        Ecto.UUID.generate(),
        ctx.board.arena_id,
        ctx.board.id,
        0,
        ctx.team.id,
        Workflows.labels(ctx.board.definition),
        ctx.steps
      )

    [first | _] = ctx.steps

    battle =
      Enum.reduce_while(1..12, start(ctx.board), fn _, battle ->
        if battle.stage == first["key"], do: {:halt, battle}, else: {:cont, step(battle)}
      end)

    assert battle.stage == first["key"]

    assert Stages.next(Map.delete(battle.snapshot, "custom_stages"), "speculator") ==
             "implementor"

    {:ok, paused} = Battles.pause(battle.id, battle.control_revision)
    assert paused.state == "paused"
    {:ok, resumed} = Battles.resume(battle.id, paused.control_revision)
    {:ok, failed} = Battles.claim_next(battle.id)

    {:ok, waiting} =
      Battles.finish(
        failed.id,
        failed.claim_token,
        result(failed, %{
          "status" => "failed",
          "reason" => "connection_lost",
          "provider" => %{"status" => "connection_lost"}
        })
      )

    {:ok, manual} = Battles.cancel_backoff(battle.id, waiting.control_revision)
    {:ok, retried} = Battles.retry(battle.id, manual.control_revision)
    assert retried.stage == first["key"]
    assert retried.turns_used == resumed.turns_used + 1
    {:ok, fresh} = Battles.claim_next(battle.id)
    assert fresh.id != failed.id and fresh.role == first["role"]
    {:ok, finished} = Battles.finish(fresh.id, fresh.claim_token, result(fresh))
    assert length(hd(Battles.tasks(battle.id)).context["read_stage_summaries"]) == 1
    assert {:ok, %{state: "stopped"}} = Battles.stop(finished.id)
  end

  defp step(battle) do
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, next} = Battles.finish(attempt.id, attempt.claim_token, result(attempt))
    next
  end

  test "all four offered read stages fit the bounded prompt for an ordinary small board", ctx do
    extra =
      for name <- ["API review", "Test review"],
          do:
            Team.custom_role()
            |> Map.merge(%{"name" => name, "agent" => "codex", "model_id" => "test-id"})

    {:ok, team} =
      Team.save(
        Ecto.UUID.generate(),
        ctx.team.id,
        Team.editable(ctx.team) ++ extra,
        false,
        ctx.board
      )

    steps =
      ctx.steps ++
        Enum.map(
          extra,
          &%{"key" => "step_" <> Ecto.UUID.generate(), "name" => &1["name"], "role" => &1["id"]}
        )

    {:ok, _} =
      Workflows.configure(
        Ecto.UUID.generate(),
        ctx.board.arena_id,
        ctx.board.id,
        0,
        team.id,
        Workflows.labels(ctx.board.definition),
        steps
      )

    assert length(Stages.custom(start(ctx.board).snapshot)) == 4
  end
end
