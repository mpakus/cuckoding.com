defmodule Cuckoding.RoleSlotsTest do
  use Cuckoding.DataCase
  import Cuckoding.BattleFixtures
  import Cuckoding.RoleSlotFixtures

  alias Cuckoding.{
    Agents,
    BattleExecutor,
    Battles,
    Command,
    Foundation,
    Repo,
    Team,
    TeamAssignments
  }

  alias Cuckoding.Battles.{Attempt, Slots}

  setup do: fixture()

  defmodule ForbiddenGit do
    def run(_, _), do: raise("native Git must not be reached")
  end

  test "native admission checks the extra binding before reaching Git", ctx do
    id = additional_connection()
    assign_worker(ctx.board, id)
    battle = start(ctx.board)
    {:ok, admission} = Battles.claim_next(battle.id)
    agent = Agents.get(id)

    Repo.update!(
      Ecto.Changeset.change(agent,
        connection: Map.put(agent.connection, "authorization", "not_connected")
      )
    )

    receipt = BattleExecutor.execute(admission, git: ForbiddenGit)
    assert receipt["status"] == "failed" and receipt["reason"] == "admission_changed"
    assert receipt["cleanup_verified"] == true
  end

  test "invalid saved slot cannot launch a host stage or fall back to another worker", ctx do
    id = additional_connection()
    assign_worker(ctx.board, id)
    battle = start(ctx.board)
    {:ok, admission} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.finish(admission.id, admission.claim_token, result(admission))
    task = hd(Battles.tasks(battle.id))
    Repo.update!(Ecto.Changeset.change(task, context: Map.put(task.context, "worker_slot", 2)))
    before = Battles.attempts(battle.id)
    assert {:error, :invalid_binding} = Battles.claim_next(battle.id)
    assert Battles.attempts(battle.id) == before
    assert Slots.binding(battle.snapshot, "implementor", 2) == nil
  end

  test "new worker choices reject foreign models, duplicate connections and forged fields", ctx do
    id = additional_connection()
    original = TeamAssignments.assigned(ctx.board)
    roles = Team.editable(original)

    for {extra, reason} <- [
          {%{"parallel_agent" => id, "parallel_model_id" => "test-id"}, "model_refresh_required"},
          {%{"parallel_agent" => Ecto.UUID.generate(), "parallel_model_id" => "worker-model"},
           "model_refresh_required"},
          {%{"parallel_agent" => "codex", "parallel_model_id" => "test-id"}, :invalid_roles},
          {%{"parallel_agent" => "", "parallel_model_id" => "worker-model"}, :invalid_roles},
          {%{
             "parallel_agent" => id,
             "parallel_model_id" => "worker-model",
             "parallel_model" => "forged"
           }, :invalid_roles}
        ] do
      changed = List.update_at(roles, 1, &Map.merge(&1, extra))

      assert {:error, ^reason} =
               Team.save(Ecto.UUID.generate(), original.id, changed, false, ctx.board)
    end

    custom =
      Team.custom_role()
      |> Map.merge(%{
        "name" => "Research",
        "parallel_agent" => id,
        "parallel_model_id" => "worker-model"
      })

    assert {:error, :invalid_roles} =
             Team.save(Ecto.UUID.generate(), original.id, roles ++ [custom], false, ctx.board)

    assert TeamAssignments.assigned(ctx.board) == original
    refute Foundation.pending?()
  end

  test "legacy omission preserves a worker without promoting or duplicating its connection",
       ctx do
    id = additional_connection()
    saved = assign_worker(ctx.board, id)
    assert saved.definition["version"] == 2
    legacy = Team.editable(saved) |> Enum.map(&Map.drop(&1, ~w(parallel_agent parallel_model_id)))
    renamed = put_in(legacy, [Access.at(1), "name"], "Renamed writer")
    assert {:ok, preserved} = Team.save(Ecto.UUID.generate(), saved.id, renamed, false, ctx.board)
    assert Enum.at(preserved.definition["roles"], 1)["parallel_agent"] == id

    copied =
      List.update_at(renamed, 1, &Map.merge(&1, %{"agent" => id, "model_id" => "worker-model"}))

    assert {:error, "worker_connection_conflict"} =
             Team.save(Ecto.UUID.generate(), preserved.id, copied, false, ctx.board)

    assert TeamAssignments.assigned(ctx.board) == preserved
  end

  test "Disconnect unassigns only the exact extra connection across current scopes", ctx do
    id = additional_connection()
    original = Team.current()

    roles =
      List.update_at(
        Team.editable(original),
        1,
        &Map.merge(&1, %{"parallel_agent" => id, "parallel_model_id" => "worker-model"})
      )

    assert {:ok, saved} = Team.save(Ecto.UUID.generate(), original.id, roles)

    for tabula <- [nil, ctx.board.id] do
      scope = if tabula, do: ctx.board, else: Cuckoding.Tabulae.arena(ctx.board.arena_id)

      assert {:ok, _} =
               TeamAssignments.adopt(
                 Ecto.UUID.generate(),
                 ctx.board.arena_id,
                 tabula,
                 TeamAssignments.assigned(scope).id,
                 saved.id,
                 true
               )
    end

    assert {:ok, _} =
             Foundation.disconnect_agent(
               Ecto.UUID.generate(),
               Foundation.workspace().revision,
               true,
               id
             )

    assert {:ok, claim} = Foundation.claim()

    assert {:ok, _} =
             Foundation.finish(claim, %{
               "status" => "checked",
               "authorization" => "not_connected",
               "catalog_status" => "not_requested",
               "cleanup_verified" => true
             })

    for team <- [
          Team.current(),
          TeamAssignments.assigned(ctx.board),
          TeamAssignments.assigned(Cuckoding.Tabulae.arena(ctx.board.arena_id))
        ] do
      role = Enum.at(team.definition["roles"], 1)

      assert Map.take(role, ~w(agent model_id model)) == %{
               "agent" => "codex",
               "model_id" => "test-id",
               "model" => "test-model"
             }

      assert role["parallel_agent"] == "" and role["parallel_model_id"] == ""
      refute Team.uses_agent?(team.definition["roles"], id)
    end

    assert Repo.get!(Cuckoding.TeamRevision, saved.id) == saved
    assert Agents.disconnected?(Agents.get(id))
  end

  test "optional workers use exact catalog bindings and scoped immutable revisions", ctx do
    original = Team.current()
    id = additional_connection()
    saved = assign_worker(ctx.board, id)
    role = Enum.find(saved.definition["roles"], &(&1["id"] == "implementor"))
    assert role["parallel_model"] == "test-model"
    assert Team.current() == original
    assert TeamAssignments.assigned(ctx.board) == saved
    command = Repo.get!(Command, saved.command_id)

    assert {:ok, ^saved} =
             Team.save(
               command.id,
               command.expected_revision,
               command.payload["roles"],
               false,
               ctx.board
             )

    assert Repo.get!(Cuckoding.TeamRevision, original.id) == original
    refute Foundation.pending?()
    {:ok, preview} = Battles.preview(ctx.board.arena_id, ctx.board.id)
    assert preview.blockers == []
    assert preview.snapshot["role_slots"] == "assigned-pairs-v1"
    assert hd(preview.snapshot["parallel_team"])["agent_id"] == id
    assert Enum.any?(preview.team, &(&1["agent_id"] == id and &1["name"] =~ "worker 2"))
    public = Cuckoding.Dashboard.board(ctx.board.arena_id, ctx.board.id).team
    assert Enum.any?(public, &(&1["agent"] == id and &1["agent_name"] == "Second writer"))
    assert Enum.all?(public, &(Map.keys(&1) -- ~w(name agent model_id agent_name) == []))
  end

  test "two writers can stay claimed together after shared primary planning turns", ctx do
    id = additional_connection()
    assign_worker(ctx.board, id)
    independent = save_task(ctx.board, "Independent writer", [])
    battle = start(ctx.board)

    writers = hold_writers(battle)

    assert length(writers) == 2
    assert Enum.sort(Enum.map(writers, & &1.task_id)) == Enum.sort([ctx.first.id, independent.id])
    assert Enum.map(writers, & &1.request["role"]["agent_id"]) == ["codex", id]
    assert Enum.map(writers, & &1.request["task_context"]["worker_slot"]) == [0, 1]
    assert {:error, :busy} = Battles.claim_next(battle.id)
    assert {:ok, pausing} = Battles.pause(battle.id, 0)
    assert pausing.state == "pausing"

    for writer <- writers,
        do: assert({:ok, _} = Battles.finish(writer.id, writer.claim_token, result(writer)))

    assert Battles.get(battle.id).state == "paused"
    assert {:ok, resumed} = Battles.resume(battle.id, Battles.get(battle.id).control_revision)
    assert resumed.snapshot == battle.snapshot

    completed =
      Enum.reduce_while(1..80, resumed, fn _, current ->
        {:ok, attempt} = Battles.claim_next(current.id)
        {:ok, next} = Battles.finish(attempt.id, attempt.claim_token, result(attempt))
        if next.state == "completed", do: {:halt, next}, else: {:cont, next}
      end)

    assert completed.state == "completed"

    final =
      Battles.attempts(battle.id)
      |> Enum.filter(&(&1.stage in ~w(final_coordinator final_secutor)))

    assert final != []
    assert Enum.all?(final, &(&1.request["role"]["agent_id"] == "codex"))
  end

  defp hold_writers(battle) do
    Enum.reduce_while(1..40, [], fn _, held ->
      assert {:ok, attempt} = Battles.claim_next(battle.id)

      cond do
        attempt.stage == "implementor" and held != [] ->
          {:halt, held ++ [attempt]}

        attempt.stage == "implementor" ->
          {:cont, [attempt]}

        true ->
          assert {:ok, _} = Battles.finish(attempt.id, attempt.claim_token, result(attempt))
          {:cont, held}
      end
    end)
  end

  test "a failed additional writer keeps its slot through a fresh bounded retry", ctx do
    id = additional_connection()
    assign_worker(ctx.board, id)
    save_task(ctx.board, "Independent retry", [])
    battle = start(ctx.board)
    [primary, extra] = hold_writers(battle)
    {:ok, _} = Battles.pause(battle.id, 0)

    failure =
      Map.take(extra.request, ~w(battle_id request_id task_id stage criteria_sha256))
      |> Map.merge(%{
        "status" => "failed",
        "reason" => "provider_error",
        "cleanup_verified" => true,
        "provider" => %{"status" => "provider_error"}
      })

    assert {:ok, _} = Battles.finish(extra.id, extra.claim_token, failure)
    assert {:ok, blocked} = Battles.finish(primary.id, primary.claim_token, result(primary))
    assert blocked.state == "needs_attention" and blocked.current_task_id == extra.task_id
    assert {:ok, retried} = Battles.retry(battle.id, blocked.control_revision)
    assert retried.snapshot == battle.snapshot
    assert retried.deadline_at == battle.deadline_at
    assert Repo.get!(Attempt, extra.id).state == "failed"
    assert {:ok, fresh} = Battles.claim_next(battle.id)
    assert fresh.stage == "prepare_worktree" and fresh.task_id == extra.task_id
    assert fresh.request["task_context"]["worker_slot"] == 1
    refute fresh.id == extra.request["task_context"]["preparation"]["key"]

    assert Slots.task_binding(
             fresh.request["snapshot"],
             "implementor",
             Enum.find(Battles.tasks(battle.id), &(&1.task_id == extra.task_id))
           )["agent_id"] == id
  end

  test "all frozen workers gate admission Resume and Disconnect without fallback", ctx do
    id = additional_connection()
    assign_worker(ctx.board, id)
    battle = start(ctx.board)
    assert {:ok, paused} = Battles.pause(battle.id, 0)

    assert {:ok, %Command{state: "rejected", result: "agent_in_battle"}} =
             Foundation.disconnect_agent(
               Ecto.UUID.generate(),
               Foundation.workspace().revision,
               true,
               id
             )

    agent = Agents.get(id)

    Repo.update!(
      Ecto.Changeset.change(agent,
        connection: Map.put(agent.connection, "authorization", "not_connected")
      )
    )

    assert {:error, :resume_binding_changed} = Battles.resume(battle.id, paused.control_revision)
    assert Slots.bindings(battle.snapshot) |> Enum.any?(&(&1["agent_id"] == id))
    {:ok, preview} = Battles.preview(ctx.board.arena_id, ctx.board.id)
    assert "connection_required" in preview.blockers
    assert Enum.find(preview.team, &(&1["agent_id"] == id))["status"] == "connection_required"
    assert Battles.attempts(battle.id) == []
  end

  test "historical snapshots ignore worker policy and final stages retain primary", ctx do
    id = additional_connection()
    assign_worker(ctx.board, id)
    battle = start(ctx.board)
    assert Slots.binding(battle.snapshot, "implementor", 0)["agent_id"] == "codex"
    assert Slots.binding(battle.snapshot, "implementor", 1)["agent_id"] == id
    legacy = Map.delete(battle.snapshot, "role_slots")
    assert Slots.binding(legacy, "implementor", 1)["agent_id"] == "codex"
    assert length(Slots.bindings(legacy)) == 4
    refute Enum.any?(Battles.attempts(battle.id), &match?(%Attempt{}, &1))
  end
end
