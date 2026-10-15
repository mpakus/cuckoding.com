defmodule Cuckoding.BattlesTest do
  use Cuckoding.DataCase
  alias Cuckoding.{Battles, Codex, Foundation, ProjectChecks, Tabulae, Team, TeamAssignments}
  alias Cuckoding.Battles.{Attempt, Battle, Snapshot}

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
              "tools" => [
                %{
                  "call_id" => Ecto.UUID.generate(),
                  "tool" => "read_file",
                  "status" => "completed",
                  "path" => "README.md",
                  "sha256" => String.duplicate("a", 64)
                }
              ]
            }
          }
      end

    envelope |> Map.merge(payload) |> Map.put("cleanup_verified", true) |> Map.merge(override)
  end

  defp step(battle, overrides \\ %{}) do
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, battle} = Battles.finish(attempt.id, attempt.claim_token, result(attempt, overrides))
    {battle, attempt}
  end

  defp until_stage(battle, stage) do
    if battle.stage == stage, do: battle, else: until_stage(elem(step(battle), 0), stage)
  end

  defp fail_provider(battle, reason \\ "provider_error", cleanup \\ true) do
    {:ok, attempt} = Battles.claim_next(battle.id)
    receipt = Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))

    receipt =
      Map.merge(receipt, %{
        "status" => "failed",
        "reason" => reason,
        "provider" => %{"status" => reason},
        "cleanup_verified" => cleanup
      })

    {:ok, battle} = Battles.finish(attempt.id, attempt.claim_token, receipt)
    {battle, Repo.get!(Attempt, attempt.id)}
  end

  test "Skip defers a diamond once, keeps paused state and survives restart", ctx do
    sibling = save_task(ctx.board, "Sibling", [ctx.first.id])
    leaf = save_task(ctx.board, "Leaf", [ctx.second.id, sibling.id])
    independent = save_task(ctx.board, "Independent", [])
    original = Tabulae.tasks(ctx.board.id)
    battle = start(ctx.board) |> until_stage("implementor")
    {:ok, paused} = Battles.pause(battle.id, 0)
    before = Battles.attempts(battle.id)
    assert length(Battles.skip_preview(paused)) == 4
    assert {:error, :stale_control} = Battles.skip(paused.id, 1, ctx.first.id, false)
    assert {:error, :stale_control} = Battles.skip(paused.id, 1, independent.id, true)
    assert {:ok, skipped} = Battles.skip(paused.id, 1, ctx.first.id, true)
    assert skipped.state == "paused"
    assert skipped.current_task_id == independent.id
    assert skipped.stage == "prepare_worktree"
    assert Battles.attempts(battle.id) == before
    assert Tabulae.tasks(ctx.board.id) == original

    assert Map.take(skipped, ~w(snapshot fingerprint deadline_at turns_used)a) ==
             Map.take(paused, ~w(snapshot fingerprint deadline_at turns_used)a)

    states = Map.new(Battles.tasks(battle.id), &{&1.task_id, &1.state})
    assert states[ctx.first.id] == "skipped"
    for id <- [ctx.second.id, sibling.id, leaf.id], do: assert(states[id] == "deferred")
    assert states[independent.id] == "pending"
    assert {:ok, _} = Battles.recover()
    assert Battles.get(battle.id).context == skipped.context
    {:ok, resumed} = Battles.resume(skipped.id, skipped.control_revision)
    {_, next} = step(resumed)
    assert next.task_id == independent.id
    assert next.request["context"]["head"] == paused.context["head"]
    assert {:error, :stale_control} = Battles.skip(paused.id, 1, ctx.first.id, true)
  end

  test "Skip of all tasks stops without review or provider claims", ctx do
    battle = start(ctx.board) |> until_stage("coordinator")
    {failed, attempt} = fail_provider(battle)
    before = Battles.attempts(battle.id)
    {:ok, stopped} = Battles.skip(failed.id, 0, ctx.first.id, true)
    assert stopped.state == "stopped"
    assert stopped.reason == "all_tasks_skipped"
    assert stopped.current_task_id == nil
    assert Battles.attempts(battle.id) == before
    assert stopped.context["skipped_attempts"] == [attempt.id]
    refute Battles.locked?(ctx.board.id)
    assert {:error, :not_running} = Battles.claim_next(stopped.id)
    refute Enum.any?(Battles.evidence(battle.id), &(&1.kind == "battle.completed"))
  end

  test "Skip keeps reviewed commits and requires final review of the partial scope", ctx do
    battle = start(ctx.board) |> until_stage("integrate")
    {battle, _} = step(battle)
    assert battle.current_task_id == ctx.second.id
    reviewed_head = battle.context["head"]
    {:ok, paused} = Battles.pause(battle.id, 0)
    {:ok, skipped} = Battles.skip(paused.id, 1, ctx.second.id, true)
    assert skipped.stage == "final_checks"
    assert skipped.state == "paused"
    assert skipped.context["head"] == reviewed_head
    {:ok, resumed} = Battles.resume(skipped.id, 2)
    {reviewing, check} = step(resumed)
    assert check.stage == "final_checks"

    assert check.request["criteria_sha256"] ==
             Snapshot.final_criteria_digest(skipped.snapshot, skipped.context)

    refute check.request["criteria_sha256"] ==
             Snapshot.final_criteria_digest(skipped.snapshot, %{})

    {summarizing, review} = step(reviewing)
    assert review.stage == "final_secutor"
    {partial, _} = step(summarizing)
    assert partial.state == "partial"
    assert partial.context["head"] == reviewed_head
    assert {:ok, ^partial} = Battles.stop(partial.id)
    refute Battles.locked?(ctx.board.id)
    assert Enum.any?(Battles.evidence(battle.id), &(&1.kind == "battle.partial"))
    refute Enum.any?(Battles.evidence(battle.id), &(&1.kind == "battle.completed"))
  end

  test "successive skips do not duplicate shared dependents", ctx do
    independent = save_task(ctx.board, "Independent", [])
    shared = save_task(ctx.board, "Shared", [ctx.second.id, independent.id])
    battle = start(ctx.board) |> until_stage("coordinator")
    {:ok, paused} = Battles.pause(battle.id, 0)
    {:ok, skipped} = Battles.skip(paused.id, 1, ctx.first.id, true)
    assert Enum.map(Battles.skip_preview(skipped), & &1.task_id) == [independent.id]
    {:ok, stopped} = Battles.skip(skipped.id, 2, independent.id, true)
    assert stopped.state == "stopped"
    assert Enum.count(stopped.context["omitted_tasks"], &(&1["id"] == shared.id)) == 1
    assert length(stopped.context["omitted_tasks"]) == 4
  end

  test "partial results cannot bypass failed configured final checks", ctx do
    battle = start(ctx.board) |> until_stage("integrate")
    {battle, _} = step(battle)
    {:ok, paused} = Battles.pause(battle.id, 0)
    {:ok, skipped} = Battles.skip(paused.id, 1, ctx.second.id, true)
    {:ok, resumed} = Battles.resume(skipped.id, 2)

    {reviewing, _} =
      step(resumed, %{
        "status" => "checks_failed",
        "checks" => [%{"id" => ctx.check["id"], "status" => "failed", "exit_code" => 1}]
      })

    {:ok, review} = Battles.claim_next(reviewing.id)

    assert {:error, :invalid_result} =
             Battles.finish(review.id, review.claim_token, result(review))

    assert Battles.get(battle.id).state == "running"
    assert Battles.skip_preview(Battles.get(battle.id)) == []
  end

  test "Skip supports blocked criteria and exhausted task review without resetting counters",
       ctx do
    independent = save_task(ctx.board, "Independent", [])

    for outcome <- ["blocked", "changes_requested"] do
      battle = start(ctx.board) |> until_stage("secutor")

      if outcome == "changes_requested" do
        task = hd(Battles.tasks(battle.id))
        Repo.update!(Ecto.Changeset.change(task, review_round: 2))
      end

      {:ok, attempt} = Battles.claim_next(battle.id)

      receipt =
        result(attempt)
        |> put_in(["provider", "report", "outcome"], outcome)
        |> Map.put("status", outcome)

      {:ok, failed} = Battles.finish(attempt.id, attempt.claim_token, receipt)
      task = hd(Battles.tasks(battle.id))
      {:ok, skipped} = Battles.skip(failed.id, 0, ctx.first.id, true)
      assert skipped.state == "running"
      assert skipped.current_task_id == independent.id
      assert hd(Battles.tasks(battle.id)).review_round == task.review_round

      assert hd(Battles.tasks(battle.id)).context["native_candidate"] ==
               task.context["native_candidate"]

      {:ok, paused} = Battles.pause(skipped.id, 1)
      assert paused.state == "paused"
      {:ok, _} = Battles.stop(battle.id)
    end
  end

  test "Skip refuses uncertain, policy, native and final-stage failures", ctx do
    for {stage, reason, clean} <- [
          {"capture", "provider_error", true},
          {"integrate", "provider_error", true},
          {"implementor", "provider_error", false},
          {"speculator", "model_mismatch", true},
          {"final_secutor", "provider_error", true}
        ] do
      {failed, _} = start(ctx.board) |> until_stage(stage) |> fail_provider(reason, clean)
      assert Battles.skip_preview(failed) == []

      assert {:error, :skip_unavailable} =
               Battles.skip(failed.id, 0, failed.current_task_id, true)

      Repo.update!(Ecto.Changeset.change(failed, state: "stopped"))
    end
  end

  test "Skip rejects old grants, exhaustion, changed bindings and active claims", ctx do
    battle = start(ctx.board) |> until_stage("implementor")
    assert Battles.skip_preview(battle) == []
    {:ok, paused} = Battles.pause(battle.id, 0)

    assert Battles.skip_preview(%{
             paused
             | snapshot: Map.delete(paused.snapshot, "task_selection")
           }) == []

    assert Battles.skip_preview(paused, paused.deadline_at) == []
    assert Battles.skip_preview(%{paused | turns_used: paused.snapshot["limits"]["turns"]}) == []
    workspace = Foundation.workspace()

    Repo.update!(
      Ecto.Changeset.change(workspace,
        connection: Map.put(workspace.connection, "authorization", "not_connected")
      )
    )

    assert {:error, :resume_binding_changed} = Battles.skip(paused.id, 1, ctx.first.id, true)
    Repo.update!(Ecto.Changeset.change(Foundation.workspace(), connection: workspace.connection))
    {:ok, resumed} = Battles.resume(paused.id, 1)
    {:ok, _} = Battles.claim_next(resumed.id)
    {:ok, pausing} = Battles.pause(resumed.id, 2)
    assert Battles.skip_preview(pausing) == []
    {:ok, _} = Battles.recover()
    assert Battles.skip_preview(Battles.get(battle.id)) == []
  end

  test "concurrent Skip confirms one graph transition", ctx do
    independent = save_task(ctx.board, "Independent", [])
    {failed, _} = start(ctx.board) |> until_stage("speculator") |> fail_provider()

    results =
      1..4
      |> Enum.map(fn _ ->
        Task.async(fn -> Battles.skip(failed.id, 0, ctx.first.id, true) end)
      end)
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :stale_control})) == 3
    assert Battles.get(failed.id).current_task_id == independent.id
    assert Enum.count(Battles.evidence(failed.id), &(&1.kind == "battle.task_skipped")) == 1
  end

  test "Retry retains failed evidence and frozen limits, then Pause/Resume still work", ctx do
    battle = start(ctx.board) |> until_stage("speculator")
    {failed, attempt} = fail_provider(battle)
    assert Battles.retry_available?(failed)
    assert {:ok, retried} = Battles.retry(failed.id, failed.control_revision)
    assert retried.stage == "speculator"
    assert retried.control_revision == failed.control_revision + 1
    assert retried.context["provider_retries"] == [attempt.id]
    assert Repo.get!(Attempt, attempt.id) == attempt

    assert Map.take(retried, ~w(snapshot fingerprint deadline_at turns_used)a) ==
             Map.take(failed, ~w(snapshot fingerprint deadline_at turns_used)a)

    assert hd(Battles.tasks(retried.id)).state == "specs"
    assert {:error, :stale_control} = Battles.retry(failed.id, failed.control_revision)
    {:ok, paused} = Battles.pause(retried.id, retried.control_revision)
    assert paused.state == "paused"
    {:ok, _} = Battles.recover()
    {:ok, resumed} = Battles.resume(paused.id, paused.control_revision)
    {_, next} = step(resumed)
    assert next.stage == attempt.stage
    refute next.id == attempt.id
    refute next.claim_token == attempt.claim_token
    assert Enum.count(Battles.evidence(failed.id), &(&1.kind == "battle.retry_requested")) == 1

    assert {:error, :stale_attempt} =
             Battles.finish(attempt.id, attempt.claim_token, result(attempt))
  end

  test "writer Retry returns through fresh preparation without resetting review counters", ctx do
    battle = start(ctx.board) |> until_stage("implementor")
    task = hd(Battles.tasks(battle.id))
    Repo.update!(Ecto.Changeset.change(task, review_round: 1))
    old_preparation = task.context["preparation"]
    {failed, attempt} = fail_provider(battle, "connection_lost")
    {:ok, retried} = Battles.retry(failed.id, failed.control_revision)
    assert retried.stage == "prepare_worktree"
    assert retried.context["head"] == battle.context["head"]
    assert hd(Battles.tasks(battle.id)).review_round == 1
    {prepared, next} = step(retried)
    assert prepared.stage == "coordinator"
    refute hd(Battles.tasks(battle.id)).context["preparation"] == old_preparation
    assert next.request["task"]["criteria"] == task.snapshot["criteria"]
    assert Repo.get!(Attempt, attempt.id) == attempt
  end

  test "two retries are shared by task stages and survive restart and concurrent clicks", ctx do
    {failed, _} = start(ctx.board) |> until_stage("coordinator") |> fail_provider()

    results =
      1..4 |> Task.async_stream(fn _ -> Battles.retry(failed.id, 0) end) |> Enum.map(&elem(&1, 1))

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :stale_control})) == 3
    battle = Battles.get(failed.id) |> until_stage("speculator")
    {failed, _} = fail_provider(battle)
    {:ok, _} = Battles.recover()
    assert {:ok, retried} = Battles.retry(failed.id, failed.control_revision)
    {exhausted, _} = fail_provider(retried)
    refute Battles.retry_available?(exhausted)
    assert {:error, :retry_unavailable} = Battles.retry(exhausted.id, exhausted.control_revision)
    assert exhausted.state == "needs_attention"
    assert length(exhausted.context["provider_retries"]) == 2
  end

  test "Retry refuses changed bindings and expired authority", ctx do
    {failed, _} = start(ctx.board) |> until_stage("speculator") |> fail_provider()
    assert {:error, :retry_unavailable} = Battles.retry(failed.id, 0, failed.deadline_at)
    workspace = Foundation.workspace()

    Repo.update!(
      Ecto.Changeset.change(workspace,
        connection: Map.put(workspace.connection, "authorization", "not_connected")
      )
    )

    assert {:error, :resume_binding_changed} = Battles.retry(failed.id, 0)
    assert Battles.get(failed.id) == failed
    Repo.update!(Ecto.Changeset.change(failed, turns_used: failed.snapshot["limits"]["turns"]))
    assert {:error, :retry_unavailable} = Battles.retry(failed.id, 0)
  end

  test "Retry refuses native errors, policy errors, blocked reviews and uncertain cleanup", ctx do
    for {stage, reason, clean} <- [
          {"admission", "provider_error", true},
          {"capture", "provider_error", true},
          {"integrate", "provider_error", true},
          {"speculator", "model_mismatch", true},
          {"implementor", "provider_error", false},
          {"implementor", "invalid_output", true}
        ] do
      {failed, _} = start(ctx.board) |> until_stage(stage) |> fail_provider(reason, clean)
      refute Battles.retry_available?(failed)
      assert {:error, :retry_unavailable} = Battles.retry(failed.id, 0)
      # End only the isolated fixture so another refusal can reuse its Arena.
      Repo.update!(Ecto.Changeset.change(failed, state: "stopped"))
    end

    battle = start(ctx.board) |> until_stage("secutor")
    {:ok, attempt} = Battles.claim_next(battle.id)

    blocked =
      result(attempt)
      |> put_in(["provider", "report", "outcome"], "blocked")
      |> Map.put("status", "blocked")

    {:ok, failed} = Battles.finish(attempt.id, attempt.claim_token, blocked)
    refute Battles.retry_available?(failed)
    assert {:error, :retry_unavailable} = Battles.retry(failed.id, 0)
  end

  test "old snapshots and interrupted claims never gain retry authority", ctx do
    {failed, attempt} = start(ctx.board) |> until_stage("speculator") |> fail_provider()
    refute Battles.retry_available?(%{failed | snapshot: Map.delete(failed.snapshot, "recovery")})

    refute Battles.retry_available?(%{
             failed
             | snapshot: put_in(failed.snapshot, ["limits", "provider_retries"], 3)
           })

    {:ok, retried} = Battles.retry(failed.id, 0)
    {:ok, _} = Battles.claim_next(retried.id)
    {:ok, _} = Battles.recover()
    refute Battles.retry_available?(Battles.get(retried.id))

    assert {:error, :stale_attempt} =
             Battles.finish(attempt.id, attempt.claim_token, attempt.result)

    assert {:error, :retry_unavailable} = Battles.retry(retried.id, retried.control_revision)
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

  test "task criteria allow Start without extra commands and still require independent reviews",
       %{board: board} do
    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), board.arena_id, 1, [], true)
    battle = start(board)
    assert battle.snapshot["version"] == "arena-loop-v2"
    battle = until_stage(battle, "final_secutor")
    assert battle.state == "running"
    {:ok, review} = Battles.claim_next(battle.id)
    no_inspection = put_in(result(review), ["provider", "tools"], [])

    assert {:error, :invalid_result} =
             Battles.finish(review.id, review.claim_token, no_inspection)

    assert {:ok, battle} = Battles.finish(review.id, review.claim_token, result(review))
    {battle, _} = step(battle)
    assert battle.state == "completed"
    attempts = Battles.attempts(battle.id)
    refute Enum.any?(attempts, &(&1.stage in ~w(checks final_checks)))
    assert Enum.count(attempts, &(&1.stage == "secutor")) == 2
    assert Enum.count(attempts, &(&1.stage == "final_secutor")) == 1
    refute Enum.any?(attempts, &Map.has_key?(&1.result, "checks"))
    event = Enum.find(Battles.evidence(battle.id), &(&1.kind == "battle.started"))
    assert event.data["command_check_count"] == 0
  end

  test "legacy snapshots cannot use the new no-command review exemption", %{board: board} do
    {:ok, preview} = Battles.preview(board.arena_id, board.id)
    snapshot = Map.merge(preview.snapshot, %{"version" => "arena-loop-v1", "checks" => []})

    battle =
      Repo.insert!(%Battle{
        id: Ecto.UUID.generate(),
        arena_id: board.arena_id,
        tabula_id: board.id,
        snapshot: snapshot,
        fingerprint: Snapshot.digest(snapshot),
        state: "running",
        stage: "final_secutor",
        context: %{"head" => String.duplicate("a", 40)},
        deadline_at: DateTime.add(DateTime.utc_now(), 600)
      })

    {:ok, attempt} = Battles.claim_next(battle.id)

    assert {:error, :invalid_result} =
             Battles.finish(attempt.id, attempt.claim_token, result(attempt))

    assert Battles.get(battle.id).state == "running"
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

  test "paused boundaries retain Arena exclusion, frozen scope and stale control protection",
       ctx do
    battle = start(ctx.board)
    {:ok, paused} = Battles.pause(battle.id, 0)
    assert paused.state == "paused"
    assert paused.control_revision == 1
    assert Battles.active?(ctx.board.arena_id)
    assert Battles.locked?(ctx.board.id, ctx.first.id)
    assert {:error, :not_running} = Battles.claim_next(battle.id)
    assert {:error, :stale_control} = Battles.pause(battle.id, 0)
    assert {:error, :stale_control} = Battles.resume(battle.id, 0)

    assert {:error, :battle_active} =
             Battles.start(
               Ecto.UUID.generate(),
               ctx.board.arena_id,
               ctx.board.id,
               battle.fingerprint,
               true
             )

    assert {:error, _} =
             Repo.query(
               "INSERT INTO battles SELECT ?, arena_id, tabula_id, fingerprint, snapshot, context, 'running', stage, current_task_id, turns_used, deadline_at, reason, inserted_at, updated_at, control_revision FROM battles WHERE id = ?",
               [Ecto.UUID.generate(), battle.id]
             )

    {:ok, resumed} = Battles.resume(battle.id, 1)
    assert resumed.state == "running"
    assert resumed.control_revision == 2

    assert Map.take(resumed, ~w(snapshot fingerprint deadline_at turns_used stage context)a) ==
             Map.take(battle, ~w(snapshot fingerprint deadline_at turns_used stage context)a)

    assert {:error, :stale_control} = Battles.pause(battle.id, 0)
    assert {:error, :stale_control} = Battles.resume(battle.id, 1)

    assert Enum.map(Battles.evidence(battle.id), & &1.kind) ==
             ~w(battle.started battle.pause_requested battle.paused battle.resumed)
  end

  test "Pause keeps the current claim active, retains its result and resumes at the next stage",
       ctx do
    battle = start(ctx.board) |> until_stage("implementor")
    {:ok, attempt} = Battles.claim_next(battle.id)
    before_pause = Battles.get(battle.id)
    {:ok, pausing} = Battles.pause(battle.id, 0)
    assert pausing.state == "pausing"
    assert Battles.active_attempt?(attempt.id, attempt.claim_token)
    assert {:error, :not_running} = Battles.claim_next(battle.id)
    assert {:error, :stale_control} = Battles.resume(battle.id, 1)
    receipt = result(attempt)
    {:ok, paused} = Battles.finish(attempt.id, attempt.claim_token, receipt)
    assert paused.state == "paused"
    assert paused.stage == "capture"
    assert Repo.get!(Attempt, attempt.id).result == receipt
    assert paused.turns_used == before_pause.turns_used
    assert {:error, :stale_attempt} = Battles.finish(attempt.id, attempt.claim_token, receipt)
    {:ok, resumed} = Battles.resume(battle.id, paused.control_revision)
    {:ok, next} = Battles.claim_next(resumed.id)
    assert next.stage == "capture"
    assert next.request["task_context"]["provider"] == receipt["provider"]
    assert Enum.count(Battles.attempts(battle.id), &(&1.stage == "implementor")) == 1
    assert resumed.deadline_at == battle.deadline_at
  end

  test "competing Pause and Resume requests commit a single control transition", ctx do
    battle = start(ctx.board)

    for {control, revision} <- [{&Battles.pause/2, 0}, {&Battles.resume/2, 1}] do
      results =
        1..4
        |> Enum.map(fn _ -> Task.async(fn -> control.(battle.id, revision) end) end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :stale_control})) == 3
    end

    assert Battles.get(battle.id).control_revision == 2
  end

  test "Pause never hides failed stages or uncertain cleanup and Stop overrides pausing", ctx do
    battle = start(ctx.board)
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.pause(battle.id, 0)

    {:ok, failed} =
      Battles.finish(
        attempt.id,
        attempt.claim_token,
        result(attempt, %{"status" => "failed", "reason" => "provider_unavailable"})
      )

    assert failed.state == "needs_attention"
    assert failed.reason == "provider_unavailable"
    {:ok, _} = Battles.stop(battle.id)

    battle = start(ctx.board)
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.pause(battle.id, 0)
    {:ok, _} = Battles.stop(battle.id)
    refute Battles.active_attempt?(attempt.id, attempt.claim_token)

    assert {:error, :stop_pending} =
             Battles.finish(attempt.id, attempt.claim_token, result(attempt))

    assert {:ok, %Battle{state: "stopped"}} =
             Battles.finish(
               attempt.id,
               attempt.claim_token,
               result(attempt, %{"status" => "cancelled"})
             )

    battle = start(ctx.board)
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.pause(battle.id, 0)

    {:ok, uncertain} =
      Battles.finish(
        attempt.id,
        attempt.claim_token,
        result(attempt, %{"cleanup_verified" => false})
      )

    assert uncertain.state == "needs_attention"
    assert uncertain.reason == "cleanup_uncertain"
    assert uncertain.stage == "admission"
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    assert {:error, :stale_control} = Battles.resume(battle.id, 1)
  end

  test "pausing preserves review returns and final completion takes precedence", ctx do
    battle = start(ctx.board) |> until_stage("secutor")
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.pause(battle.id, 0)

    receipt =
      result(attempt, %{"status" => "changes_requested"})
      |> put_in(["provider", "report", "outcome"], "changes_requested")

    {:ok, paused} = Battles.finish(attempt.id, attempt.claim_token, receipt)
    assert paused.state == "paused"
    assert paused.stage == "prepare_worktree"
    assert hd(Battles.tasks(battle.id)).review_round == 1
    {:ok, resumed} = Battles.resume(battle.id, 1)
    battle = until_stage(resumed, "summary")
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.pause(battle.id, 2)
    {:ok, complete} = Battles.finish(attempt.id, attempt.claim_token, result(attempt))
    assert complete.state == "completed"
    assert {:error, :stale_control} = Battles.resume(battle.id, 3)
  end

  test "Resume cannot reset deadlines, turn limits or changed connection bindings", ctx do
    battle = start(ctx.board)
    {:ok, _} = Battles.pause(battle.id, 0)
    workspace = Foundation.workspace()

    Repo.update!(
      Ecto.Changeset.change(workspace,
        connection: Map.put(workspace.connection, "authorization", "not_connected")
      )
    )

    assert {:error, :resume_binding_changed} = Battles.resume(battle.id, 1)
    assert Battles.get(battle.id).state == "paused"
    Repo.update!(Ecto.Changeset.change(Foundation.workspace(), connection: workspace.connection))
    assert {:error, "deadline_exceeded"} = Battles.resume(battle.id, 1, battle.deadline_at)
    assert Battles.get(battle.id).deadline_at == battle.deadline_at
    {:ok, _} = Battles.stop(battle.id)
    battle = start(ctx.board)
    {:ok, paused} = Battles.pause(battle.id, 0)
    Repo.update!(Ecto.Changeset.change(paused, turns_used: paused.snapshot["limits"]["turns"]))
    assert {:error, "turn_limit"} = Battles.resume(battle.id, 1)
    assert Battles.get(battle.id).turns_used == paused.snapshot["limits"]["turns"]
  end

  test "restart preserves a clean pause but never resumes an interrupted pausing worker", ctx do
    battle = start(ctx.board) |> until_stage("implementor")
    {:ok, paused} = Battles.pause(battle.id, 0)
    assert {:ok, [^paused]} = Battles.recover()
    assert {:error, :not_running} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.resume(battle.id, 1)
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.pause(battle.id, 2)
    {:ok, [recovered]} = Battles.recover()
    assert recovered.state == "needs_attention"
    assert Repo.get!(Attempt, attempt.id).state == "interrupted"
    assert {:error, :stale_control} = Battles.resume(battle.id, 3)
    assert {:error, :cleanup_required} = Battles.stop(battle.id)

    assert {:error, :stale_attempt} =
             Battles.finish(attempt.id, attempt.claim_token, result(attempt))
  end

  test "restart pauses every settled boundary without replay or changing authority", ctx do
    for stage <-
          ~w(admission prepare_worktree coordinator speculator implementor capture checks secutor integrate final_checks final_secutor summary) do
      battle = start(ctx.board) |> until_stage(stage)
      attempts = Battles.attempts(battle.id)
      tasks = Battles.tasks(battle.id)
      assert {:ok, [recovered]} = Battles.recover()
      assert recovered.state == "paused"
      assert recovered.reason == "restart_checkpoint"
      assert recovered.control_revision == battle.control_revision + 1

      assert Map.take(
               recovered,
               ~w(stage current_task_id context snapshot fingerprint deadline_at turns_used)a
             ) ==
               Map.take(
                 battle,
                 ~w(stage current_task_id context snapshot fingerprint deadline_at turns_used)a
               )

      assert Battles.attempts(battle.id) == attempts
      assert Battles.tasks(battle.id) == tasks
      assert Battles.active?(ctx.board.arena_id)
      assert Battles.locked?(ctx.board.id)
      assert {:error, :not_running} = Battles.claim_next(battle.id)
      assert {:ok, [^recovered]} = Battles.recover()
      assert Enum.count(Battles.evidence(battle.id), &(&1.kind == "battle.recovery_paused")) == 1
      assert {:error, :stale_control} = Battles.resume(battle.id, battle.control_revision)
      {:ok, resumed} = Battles.resume(battle.id, recovered.control_revision)
      assert resumed.reason == nil
      {_, next} = step(resumed)
      assert next.stage == stage
      refute next.id in Enum.map(attempts, & &1.id)
      {:ok, _} = Battles.stop(battle.id)
    end
  end

  test "restart preserves consumed retries, skipped tasks and partial final scope", ctx do
    independent = save_task(ctx.board, "Independent", [])
    {failed, _} = start(ctx.board) |> until_stage("implementor") |> fail_provider()
    {:ok, retried} = Battles.retry(failed.id, 0)
    {:ok, [recovered]} = Battles.recover()
    assert recovered.state == "paused"
    assert recovered.context == retried.context
    {:ok, resumed} = Battles.resume(recovered.id, recovered.control_revision)
    {failed, _} = until_stage(resumed, "implementor") |> fail_provider()
    {:ok, skipped} = Battles.skip(failed.id, failed.control_revision, ctx.first.id, true)
    {:ok, [recovered]} = Battles.recover()
    assert recovered.state == "paused"
    assert recovered.context == skipped.context
    assert recovered.current_task_id == independent.id
    {:ok, resumed} = Battles.resume(recovered.id, recovered.control_revision)
    final = until_stage(resumed, "final_secutor")
    {:ok, [recovered]} = Battles.recover()
    assert recovered.context == final.context
    {:ok, resumed} = Battles.resume(recovered.id, recovered.control_revision)
    {summarizing, review} = step(resumed)

    assert review.request["criteria_sha256"] ==
             Snapshot.final_criteria_digest(final.snapshot, final.context)

    {partial, _} = step(summarizing)
    assert partial.state == "partial"
  end

  test "recovered checkpoints keep expired budgets and changed bindings blocked", ctx do
    battle = start(ctx.board) |> until_stage("implementor")
    {:ok, [recovered]} = Battles.recover()
    workspace = Foundation.workspace()

    Repo.update!(
      Ecto.Changeset.change(workspace,
        connection: Map.put(workspace.connection, "authorization", "not_connected")
      )
    )

    assert {:error, :resume_binding_changed} =
             Battles.resume(battle.id, recovered.control_revision)

    Repo.update!(Ecto.Changeset.change(Foundation.workspace(), connection: workspace.connection))

    assert {:error, "deadline_exceeded"} =
             Battles.resume(battle.id, recovered.control_revision, battle.deadline_at)

    assert Battles.get(battle.id).deadline_at == battle.deadline_at
    {:ok, _} = Battles.stop(battle.id)

    battle = start(ctx.board) |> until_stage("speculator")
    Repo.update!(Ecto.Changeset.change(battle, turns_used: battle.snapshot["limits"]["turns"]))
    {:ok, [recovered]} = Battles.recover()
    assert {:error, "turn_limit"} = Battles.resume(battle.id, recovered.control_revision)
    assert Battles.get(battle.id).turns_used == battle.snapshot["limits"]["turns"]
  end

  test "restart cannot infer cleanup or skip an unconsumed failure", ctx do
    battle = start(ctx.board)
    {battle, _} = step(battle, %{"cleanup_verified" => false})
    {:ok, [recovered]} = Battles.recover()
    assert recovered.state == "needs_attention"
    assert recovered.reason == "restart_requires_inspection"
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    Repo.update!(Ecto.Changeset.change(recovered, state: "stopped"))

    {failed, _} = start(ctx.board) |> until_stage("speculator") |> fail_provider()
    # Simulate an older/invalid projection without granting a Retry transition.
    Repo.update!(Ecto.Changeset.change(failed, state: "running"))
    {:ok, [recovered]} = Battles.recover()
    assert recovered.state == "needs_attention"
    assert Battles.skip_preview(recovered) == []
    refute Battles.retry_available?(recovered)
  end

  test "settled pausing checkpoint recovers once while stopping remains conservative", ctx do
    battle = start(ctx.board) |> until_stage("capture")
    Repo.update!(Ecto.Changeset.change(battle, state: "pausing", control_revision: 1))
    {:ok, [recovered]} = Battles.recover()
    assert recovered.state == "paused"
    assert recovered.control_revision == 2
    assert {:ok, [^recovered]} = Battles.recover()
    Repo.update!(Ecto.Changeset.change(recovered, state: "stopping"))
    {:ok, [attention]} = Battles.recover()
    assert attention.state == "needs_attention"
    assert attention.reason == "restart_requires_inspection"
  end

  test "Pause cannot treat historical missing cleanup as a verified boundary or unlock the Arena",
       ctx do
    battle = start(ctx.board)
    {battle, _} = step(battle, %{"cleanup_verified" => false})
    assert {:error, "cleanup_uncertain"} = Battles.pause(battle.id, 0)
    assert Battles.get(battle.id).state == "needs_attention"
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    assert Battles.active?(ctx.board.arena_id)
  end

  test "pausing cannot admit a late result or extend an active claim", ctx do
    battle = start(ctx.board)
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.pause(battle.id, 0)
    refute Battles.active_attempt?(attempt.id, attempt.claim_token, attempt.deadline_at)

    assert {:error, "late_result_rejected"} =
             Battles.finish(attempt.id, attempt.claim_token, result(attempt), attempt.deadline_at)

    assert Battles.get(battle.id).state == "needs_attention"
    assert {:error, :stale_control} = Battles.resume(battle.id, 1)
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
