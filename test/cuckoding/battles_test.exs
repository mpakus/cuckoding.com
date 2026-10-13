defmodule Cuckoding.BattlesTest do
  use Cuckoding.DataCase
  alias Cuckoding.{Battles, Codex, Foundation, ProjectChecks, Tabulae, Team, TeamAssignments}
  alias Cuckoding.Battles.{Attempt, Battle}

  setup do
    %{board: board} = Cuckoding.PlanningFixtures.planning_fixture()
    workspace = Foundation.workspace()

    Repo.update!(
      Ecto.Changeset.change(workspace,
        codex: Map.put(workspace.codex, "version", Codex.isolation_version())
      )
    )

    team = Team.current()

    roles =
      Enum.map(
        Team.editable(team),
        &Map.merge(&1, %{"agent" => "codex", "model_id" => "test-id"})
      )

    {:ok, team} = Team.save(Ecto.UUID.generate(), team.id, roles)

    {:ok, _} =
      TeamAssignments.adopt(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        board.team_revision_id,
        team.id,
        true
      )

    check = %{
      "id" => Ecto.UUID.generate(),
      "name" => "Tests",
      "executable" => "mix",
      "arguments" => ["test"],
      "directory" => ".",
      "timeout_seconds" => 120
    }

    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), board.arena_id, 0, [check], true)
    first = save_task(board, "First", [])
    second = save_task(board, "Second", [first.id])
    %{board: board, first: first, second: second, check: check}
  end

  defp save_task(board, title, dependencies) do
    {:ok, _} =
      Tabulae.save(Ecto.UUID.generate(), board.arena_id, board.id, Ecto.UUID.generate(), 0, %{
        "title" => title,
        "description" => "Implement #{title}",
        "criteria" => "Retain all acceptance criteria #{title}",
        "column" => "specs",
        "depends_on" => dependencies
      })

    Enum.find(Tabulae.tasks(board.id), &(&1.title == title))
  end

  defp start(board) do
    {:ok, preview} = Battles.preview(board.arena_id, board.id)
    assert preview.blockers == []

    {:ok, battle} =
      Battles.start(Ecto.UUID.generate(), board.arena_id, board.id, preview.fingerprint, true)

    battle
  end

  defp result(attempt, override \\ %{}) do
    envelope = Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))

    candidate =
      attempt.request["task_context"]["candidate_sha"] || attempt.request["context"]["head"]

    payload =
      case attempt.stage do
        "admission" ->
          %{
            "status" => "admitted",
            "head" => String.duplicate("a", 40),
            "native_battle" => %{"reference" => "refs/ccoding/battles/#{attempt.battle_id}"},
            "resolved_checks" => attempt.request["snapshot"]["checks"]
          }

        "prepare_worktree" ->
          %{
            "status" => "prepared",
            "preparation" => %{"key" => attempt.id, "head" => attempt.request["context"]["head"]}
          }

        "capture" ->
          %{
            "status" => "captured",
            "candidate_sha" => Base.encode16(:crypto.hash(:sha, attempt.id), case: :lower),
            "native_candidate" => %{"key" => attempt.id}
          }

        stage when stage in ~w(checks final_checks) ->
          %{
            "status" => "passed",
            "candidate_sha" => candidate,
            "checks" =>
              Enum.map(
                attempt.request["snapshot"]["checks"],
                &%{"id" => &1["id"], "status" => "passed", "exit_code" => 0}
              )
          }

        "integrate" ->
          %{
            "status" => "integrated",
            "candidate_sha" => candidate,
            "head" => candidate,
            "native_battle" => %{"head" => candidate}
          }

        _ ->
          %{
            "status" => "completed",
            "candidate_sha" => candidate,
            "provider" => %{
              "status" => "task_finished",
              "request_id" => attempt.id,
              "grant" => "host-task-tools-v1",
              "access" => if(attempt.stage == "implementor", do: "write", else: "read"),
              "requested_model" => "test-model",
              "observed_model" => "test-model",
              "effort" => "low",
              "thread_id" => Ecto.UUID.generate(),
              "turn_id" => Ecto.UUID.generate(),
              "report" => %{"summary" => "Public evidence", "outcome" => "completed"},
              "tools" => []
            }
          }
      end

    envelope |> Map.merge(payload) |> Map.merge(override)
  end

  defp step(battle, overrides \\ %{}) do
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, battle} = Battles.finish(attempt.id, attempt.claim_token, result(attempt, overrides))
    {battle, attempt}
  end

  defp until_stage(battle, stage) do
    if battle.stage == stage, do: battle, else: until_stage(elem(step(battle), 0), stage)
  end

  test "one Start freezes a two-task graph, preserves criteria through rejection and finishes independently",
       %{board: board, first: first, second: second} do
    original = Tabulae.tasks(board.id)
    battle = start(board)
    assert Enum.map(battle.snapshot["tasks"], & &1["id"]) == [first.id, second.id]
    assert Battles.locked?(board.id, first.id)

    assert {:ok, ^battle} =
             Battles.start(battle.id, board.arena_id, board.id, battle.fingerprint, true)

    assert {:error, :battle_active} =
             Battles.start(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               battle.fingerprint,
               true
             )

    battle = until_stage(battle, "secutor")
    {:ok, attempt} = Battles.claim_next(battle.id)

    rejected =
      result(attempt)
      |> put_in(["provider", "report", "outcome"], "changes_requested")
      |> Map.put("status", "changes_requested")

    {:ok, battle} = Battles.finish(attempt.id, attempt.claim_token, rejected)
    assert battle.stage == "prepare_worktree"
    assert hd(Battles.tasks(battle.id)).review_round == 1
    {battle, preparation} = step(battle)
    assert preparation.request["task"]["criteria"] == first.criteria
    assert preparation.request["task_context"]["feedback"] == "Public evidence"
    battle = until_stage(battle, "integrate")
    {battle, integration} = step(battle)
    assert battle.current_task_id == second.id
    {battle, dependency_preparation} = step(battle)

    assert dependency_preparation.request["context"]["head"] ==
             integration.request["task_context"]["candidate_sha"]

    battle = until_stage(battle, "summary")
    assert battle.state == "running"
    assert Enum.all?(Battles.tasks(battle.id), &(&1.state == "completed"))
    {battle, _} = step(battle)
    assert battle.state == "completed"
    assert Tabulae.tasks(board.id) == original
    refute Battles.locked?(board.id)
    assert Enum.count(Battles.attempts(battle.id), &(&1.stage == "final_secutor")) == 1
    assert Enum.any?(Battles.evidence(battle.id), &(&1.kind == "battle.completed"))
  end

  test "editing a completed task shows the new draft without reusing its old completion", %{
    board: board,
    first: first
  } do
    battle = start(board) |> until_stage("summary")
    {_, _} = step(battle)
    assert Battles.projections(board.id)[first.id].state == "completed"

    assert {:ok, _} =
             Tabulae.save(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               first.id,
               first.revision,
               Map.put(Tabulae.content(first), "criteria", "New work is required")
             )

    refute Map.has_key?(Battles.projections(board.id), first.id)
    assert hd(Battles.tasks(battle.id)).state == "completed"
  end

  test "Start rejects changed task/check/team scope and unknown confirmation", %{
    board: board,
    first: first
  } do
    {:ok, preview} = Battles.preview(board.arena_id, board.id)

    assert {:error, :confirmation_required} =
             Battles.start(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               preview.fingerprint,
               false
             )

    attrs = Map.put(Tabulae.content(first), "criteria", "A changed criterion")

    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        first.id,
        first.revision,
        attrs
      )

    assert {:error, :stale_start} =
             Battles.start(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               preview.fingerprint,
               true
             )

    assert {:error, :scope_missing} = Battles.preview(Ecto.UUID.generate(), board.id)
  end

  test "missing checks block Start and empty/foreign check receipts cannot pass", %{board: board} do
    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), board.arena_id, 1, [], true)
    {:ok, preview} = Battles.preview(board.arena_id, board.id)
    assert "checks_required" in preview.blockers

    assert {:error, {:not_ready, _}} =
             Battles.start(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               preview.fingerprint,
               true
             )
  end

  test "duplicate claims, foreign, late and reused provider sessions are refused", %{board: board} do
    battle = start(board)
    {:ok, attempt} = Battles.claim_next(battle.id)
    assert {:error, :busy} = Battles.claim_next(battle.id)

    assert {:error, :foreign_result} =
             Battles.finish(
               attempt.id,
               attempt.claim_token,
               result(attempt, %{"task_id" => Ecto.UUID.generate()})
             )

    assert {:error, :stale_attempt} =
             Battles.finish(attempt.id, Ecto.UUID.generate(), result(attempt))

    {:ok, battle} = Battles.finish(attempt.id, attempt.claim_token, result(attempt))

    assert {:error, :stale_attempt} =
             Battles.finish(attempt.id, attempt.claim_token, result(attempt))

    {battle, _} = step(battle)
    {battle, coordinator} = step(battle)
    {:ok, speculator} = Battles.claim_next(battle.id)
    prior = Repo.get!(Attempt, coordinator.id).result["provider"]
    reused = result(speculator) |> put_in(["provider", "thread_id"], prior["thread_id"])

    assert {:error, :invalid_result} =
             Battles.finish(speculator.id, speculator.claim_token, reused)

    assert {:error, "late_result_rejected"} =
             Battles.finish(
               speculator.id,
               speculator.claim_token,
               result(speculator),
               speculator.deadline_at
             )

    assert Battles.get(battle.id).state == "needs_attention"
  end

  test "Stop immediately closes admission and waits for verified cancellation", %{board: board} do
    battle = start(board)
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, stopping} = Battles.stop(battle.id)
    assert stopping.state == "stopping"
    refute Battles.active_attempt?(attempt.id, attempt.claim_token)
    assert {:error, :not_running} = Battles.claim_next(battle.id)

    assert {:error, :stop_pending} =
             Battles.finish(attempt.id, attempt.claim_token, result(attempt))

    cancelled =
      Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))
      |> Map.merge(%{"status" => "cancelled", "cleanup_verified" => true})

    assert {:ok, %Battle{state: "stopped"}} =
             Battles.finish(attempt.id, attempt.claim_token, cancelled)

    assert {:error, :stale_attempt} =
             Battles.finish(attempt.id, attempt.claim_token, result(attempt))
  end

  test "restart retains uncertain effects and Stop cannot unlock a second battle", %{board: board} do
    battle = start(board)
    {:ok, attempt} = Battles.claim_next(battle.id)
    assert {:ok, [_]} = Battles.recover()
    assert Repo.get!(Attempt, attempt.id).state == "interrupted"
    assert Battles.get(battle.id).state == "needs_attention"
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    assert Battles.active?(board.arena_id)

    assert {:error, :battle_active} =
             Battles.start(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               battle.fingerprint,
               true
             )

    assert {:error, :not_running} = Battles.claim_next(battle.id)

    assert {:error, :stale_attempt} =
             Battles.finish(attempt.id, attempt.claim_token, result(attempt))

    assert {:ok, []} = Battles.recover()
  end

  test "known failed admission can stop after cleanup but unverified failure cannot", %{
    board: board
  } do
    battle = start(board)
    {:ok, attempt} = Battles.claim_next(battle.id)

    failure =
      result(attempt, %{
        "status" => "failed",
        "reason" => "checks_unavailable",
        "cleanup_verified" => true
      })

    assert {:ok, %Battle{state: "needs_attention"}} =
             Battles.finish(attempt.id, attempt.claim_token, failure)

    assert {:ok, %Battle{state: "stopped"}} = Battles.stop(battle.id)
    battle = start(board)
    {:ok, attempt} = Battles.claim_next(battle.id)

    failure =
      result(attempt, %{
        "status" => "failed",
        "reason" => "transport_uncertain",
        "cleanup_verified" => false
      })

    assert {:ok, %Battle{state: "needs_attention"}} =
             Battles.finish(attempt.id, attempt.claim_token, failure)

    assert {:error, :cleanup_required} = Battles.stop(battle.id)
  end

  test "checks and Secutor bind the exact candidate, model, access and all frozen criteria", %{
    board: board
  } do
    battle = start(board) |> until_stage("checks")
    {:ok, attempt} = Battles.claim_next(battle.id)

    for patch <- [
          %{"checks" => []},
          %{"checks" => ["malformed"]},
          %{"candidate_sha" => String.duplicate("f", 40)}
        ] do
      assert {:error, :invalid_result} =
               Battles.finish(attempt.id, attempt.claim_token, result(attempt, patch))
    end

    assert {:error, :foreign_result} =
             Battles.finish(
               attempt.id,
               attempt.claim_token,
               result(attempt, %{"criteria_sha256" => "dropped"})
             )

    {:ok, battle} = Battles.finish(attempt.id, attempt.claim_token, result(attempt))
    {:ok, attempt} = Battles.claim_next(battle.id)

    for {field, value} <- [
          {"observed_model", "different"},
          {"access", "write"},
          {"request_id", Ecto.UUID.generate()},
          {"private_provider_text", "must not persist"}
        ] do
      changed = put_in(result(attempt), ["provider", field], value)
      assert {:error, :invalid_result} = Battles.finish(attempt.id, attempt.claim_token, changed)
    end

    assert Battles.get(battle.id).stage == "secutor"
  end

  test "three review returns exhaust the original counter and never complete the card", %{
    board: board
  } do
    battle = start(board)

    battle =
      Enum.reduce(1..3, battle, fn round, battle ->
        battle = until_stage(battle, "secutor")
        {:ok, attempt} = Battles.claim_next(battle.id)

        rejected =
          result(attempt)
          |> put_in(["provider", "report", "outcome"], "changes_requested")
          |> Map.put("status", "changes_requested")

        {:ok, battle} = Battles.finish(attempt.id, attempt.claim_token, rejected)
        assert hd(Battles.tasks(battle.id)).review_round == round
        battle
      end)

    assert battle.state == "needs_attention"
    assert battle.reason == "review_limit"
    refute Enum.any?(Battles.tasks(battle.id), &(&1.state == "completed"))
    assert {:error, :not_running} = Battles.claim_next(battle.id)
  end

  test "Start refuses oversized Unicode task input without truncating the frozen criteria", %{
    board: board,
    first: first
  } do
    criteria = String.duplicate("🧭", 4000)
    attrs = Map.put(Tabulae.content(first), "criteria", criteria)

    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        first.id,
        first.revision,
        attrs
      )

    {:ok, preview} = Battles.preview(board.arena_id, board.id)
    assert "prompt_scope_too_large" in preview.blockers
    assert Enum.find(preview.tasks, &(&1["id"] == first.id))["criteria"] == criteria

    assert {:error, {:not_ready, reasons}} =
             Battles.start(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               preview.fingerprint,
               true
             )

    assert "prompt_scope_too_large" in reasons
  end

  test "Start bounds the final combined review independently of each individual task", %{
    board: board
  } do
    for index <- 1..18, do: save_task(board, "Additional #{index}", [])

    for task <- Tabulae.tasks(board.id) do
      attrs = Map.put(Tabulae.content(task), "criteria", String.duplicate("a", 2000))

      {:ok, _} =
        Tabulae.save(
          Ecto.UUID.generate(),
          board.arena_id,
          board.id,
          task.id,
          task.revision,
          attrs
        )
    end

    {:ok, preview} = Battles.preview(board.arena_id, board.id)
    assert length(preview.tasks) == 20
    assert preview.blockers == ["prompt_scope_too_large"]
    assert Enum.all?(preview.tasks, &(byte_size(Jason.encode!(&1)) < 24_576))

    assert {:error, {:not_ready, ["prompt_scope_too_large"]}} =
             Battles.start(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               preview.fingerprint,
               true
             )
  end

  test "Start reserves literal check declarations and escaped public summary bytes", %{
    board: board,
    check: check
  } do
    large = Map.put(check, "arguments", List.duplicate(String.duplicate("\\", 256), 16))
    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), board.arena_id, 1, [large], true)
    {:ok, preview} = Battles.preview(board.arena_id, board.id)
    assert preview.blockers == ["prompt_scope_too_large"]
    assert preview.checks == [large]
  end

  test "ordinary failed checks retain evidence and require Secutor rejection before bounded correction",
       %{board: board, check: check} do
    second_check = Map.merge(check, %{"id" => Ecto.UUID.generate(), "name" => "Second check"})

    {:ok, _} =
      ProjectChecks.save(Ecto.UUID.generate(), board.arena_id, 1, [check, second_check], true)

    battle = start(board) |> until_stage("checks")
    {:ok, attempt} = Battles.claim_next(battle.id)

    failed = %{
      "id" => check["id"],
      "status" => "failed",
      "exit_code" => 1,
      "stdout_sha256" => String.duplicate("a", 64)
    }

    failed_result =
      result(attempt, %{
        "status" => "checks_failed",
        "checks" => [failed],
        "cleanup_verified" => true
      })

    assert {:error, :invalid_result} =
             Battles.finish(
               attempt.id,
               attempt.claim_token,
               Map.put(failed_result, "cleanup_verified", false)
             )

    assert {:ok, battle} = Battles.finish(attempt.id, attempt.claim_token, failed_result)
    assert battle.state == "running"
    assert battle.stage == "secutor"
    assert Repo.get!(Attempt, attempt.id).result["checks"] == [failed]
    {:ok, review} = Battles.claim_next(battle.id)
    assert review.request["task_context"]["checks"] == [failed]

    assert {:error, :invalid_result} =
             Battles.finish(review.id, review.claim_token, result(review))

    rejected =
      result(review)
      |> put_in(["provider", "report", "outcome"], "changes_requested")
      |> Map.put("status", "changes_requested")

    {:ok, battle} = Battles.finish(review.id, review.claim_token, rejected)
    assert battle.stage == "prepare_worktree"
    assert hd(Battles.tasks(battle.id)).review_round == 1
    battle = until_stage(battle, "summary")
    {battle, _} = step(battle)
    assert battle.state == "completed"
    assert Repo.get!(Attempt, attempt.id).result["status"] == "checks_failed"
  end

  test "final review cannot pass failed final checks and uncertain checks require attention", %{
    board: board
  } do
    battle = start(board) |> until_stage("final_checks")
    {:ok, attempt} = Battles.claim_next(battle.id)

    failed =
      result(attempt)["checks"] |> hd() |> Map.merge(%{"status" => "failed", "exit_code" => 2})

    {:ok, battle} =
      Battles.finish(
        attempt.id,
        attempt.claim_token,
        result(attempt, %{
          "status" => "checks_failed",
          "checks" => [failed],
          "cleanup_verified" => true
        })
      )

    assert battle.stage == "final_secutor"
    {:ok, review} = Battles.claim_next(battle.id)

    assert {:error, :invalid_result} =
             Battles.finish(review.id, review.claim_token, result(review))

    rejected =
      result(review)
      |> put_in(["provider", "report", "outcome"], "changes_requested")
      |> Map.put("status", "changes_requested")

    {:ok, battle} = Battles.finish(review.id, review.claim_token, rejected)
    assert battle.state == "needs_attention"
    assert battle.reason == "final_review_changes_requested"
    {:ok, _} = Battles.stop(battle.id)
    battle = start(board) |> until_stage("checks")
    {:ok, attempt} = Battles.claim_next(battle.id)

    {:ok, battle} =
      Battles.finish(
        attempt.id,
        attempt.claim_token,
        result(attempt, %{
          "status" => "failed",
          "reason" => "cleanup_uncertain",
          "cleanup_verified" => false
        })
      )

    assert battle.state == "needs_attention"
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
  end
end
