defmodule Cuckoding.BattleExecutorTest do
  use Cuckoding.DataCase

  alias Cuckoding.{
    Agents,
    ArenaGit,
    Arenas,
    BattleExecutor,
    BattleRunner,
    Battles,
    Codex,
    Cursor,
    Foundation,
    ProjectChecks,
    Storage,
    Tabulae,
    Team,
    TeamAssignments
  }

  alias Cuckoding.Battles.{Attempt, Backoff, ProviderClosure, Snapshot}

  # These adapters exercise the real executor/domain handoff without native or provider execution.
  defmodule Adapters do
    import ExUnit.Assertions
    alias Cuckoding.ArenaGit

    def run(%{id: id, payload: payload}, options) do
      assert options[:active?].()
      remember(:git_calls, {payload["operation"], id, payload})
      git(payload["operation"], id, payload)
    end

    defp git("inspect", _, _), do: %{"status" => "existing", "head" => String.duplicate("a", 40)}

    defp git("create_battle", _, %{"request" => request}) do
      %{
        "status" => "battle_created",
        "key" => request["key"],
        "battle_key" => request["key"],
        "base" => request["head"],
        "head" => request["head"],
        "reference" => "refs/heads/ccoding/battles/" <> request["key"],
        "manifest_sha256" => String.duplicate("a", 64)
      }
    end

    defp git("battle_worktree", _, %{"request" => request}) do
      head =
        if(request["candidate"],
          do: request["candidate"]["candidate"],
          else: request["battle"]["head"]
        )

      if request["candidate"],
        do: assert(request["candidate"]["base"] == request["battle"]["head"])

      %{
        "status" => "prepared",
        "key" => request["key"],
        "head" => head,
        "path" => ArenaGit.worktree_path(request["key"]),
        "device" => 1,
        "inode" => 1
      }
    end

    defp git("inspect_worktree", _, %{"preparation" => preparation}),
      do: Map.put(preparation, "status", "worktree_unchanged")

    defp git("verify_battle", _, %{"request" => request}),
      do: Map.put(request["battle"], "status", "battle_verified")

    defp git("capture_candidate", id, payload) do
      assert [%{"path" => "feature.txt", "sha256" => sha}] = payload["files"]
      assert byte_size(sha) == 64

      %{
        "status" => "candidate_captured",
        "key" => id,
        "worktree_key" => payload["preparation"]["key"],
        "base" => payload["preparation"]["head"],
        "candidate" => digest(id),
        "tree" => digest("tree:" <> id),
        "manifest_sha256" => String.duplicate("b", 64)
      }
    end

    defp git("combine_candidate", id, %{"request" => request}) do
      %{
        "status" => "candidate_combined",
        "key" => id,
        "battle_key" => request["battle"]["battle_key"],
        "worktree_key" => request["preparation"]["key"],
        "task_candidate_key" => request["candidate"]["key"],
        "base" => request["battle"]["head"],
        "task_base" => request["preparation"]["head"],
        "candidate" => digest("combined:" <> id),
        "tree" => digest("tree:" <> id),
        "manifest_sha256" => String.duplicate("a", 64)
      }
    end

    defp git("integrate_candidate", id, %{"request" => request}) do
      assert request["candidate"]["base"] == request["battle"]["head"]

      request["battle"]
      |> Map.merge(%{
        "status" => "battle_integrated",
        "key" => id,
        "previous_head" => request["battle"]["head"],
        "head" => request["candidate"]["candidate"],
        "candidate_key" => request["candidate"]["key"]
      })
    end

    defp git("recover_integration", id, payload), do: git("integrate_candidate", id, payload)

    def resolve(checks) do
      assert checks != [], "Empty command scopes must never reach native command resolution"
      {:ok, Enum.map(checks, &Map.merge(&1, %{"identity" => %{}, "rtk_identity" => %{}}))}
    end

    def run(attempt, workspace, checks, _identity, active?) do
      assert active?.()
      remember(:check_calls, {attempt.stage, workspace, checks})
      fail? = Process.get(:fail_first_check, false) and length(Process.get(:check_calls)) == 1

      receipts =
        Enum.map(
          checks,
          &%{
            "id" => &1["id"],
            "status" => if(fail?, do: "failed", else: "passed"),
            "exit_code" => if(fail?, do: 1, else: 0),
            "stdout_sha256" => String.duplicate("c", 64),
            "stdout_bytes" => 12,
            "pid" => 101,
            "spawned_at_ms" => 1000,
            "elapsed_ms" => 1,
            "cleanup_verified" => true
          }
        )

      %{
        "status" => if(fail?, do: "failed", else: "passed"),
        "candidate_sha" => workspace["head"],
        "checks" => receipts,
        "cleanup_verified" => true
      }
    end

    def run_task(identity, _profile, _scratch, request, active?) do
      assert active?.()
      prompt = Jason.decode!(request["prompt"])
      assert byte_size(request["prompt"]) <= 32_768
      remember(:provider_calls, {prompt, request, identity})
      outcome = outcome(prompt)

      changes =
        if(request["access"] == "write",
          do: [%{"path" => "feature.txt", "sha256" => String.duplicate("d", 64)}],
          else: []
        )

      tools =
        Enum.map(
          changes,
          &Map.merge(&1, %{
            "tool" => "edit_file",
            "call_id" => Ecto.UUID.generate(),
            "status" => "completed"
          })
        )

      tools =
        if request["access"] == "read" do
          [
            %{
              "tool" => "read_file",
              "call_id" => Ecto.UUID.generate(),
              "status" => "completed",
              "path" => "feature.txt",
              "sha256" => String.duplicate("d", 64)
            }
          ]
        else
          tools
        end

      receipt = %{
        "status" => "task_finished",
        "request_id" => request["request_id"],
        "requested_model" => request["model"],
        "observed_model" => Process.get(:observed_model, request["model"]),
        "effort" => request["effort"],
        "transport" => if(request["model"] == "cursor-test", do: "cursor-acp-v1"),
        "runtime_model" => if(request["model"] == "cursor-test", do: "test"),
        "runtime_parameters" => if(request["model"] == "cursor-test", do: %{"effort" => "xhigh"}),
        "grant" => "host-task-tools-v1",
        "access" => request["access"],
        "thread_id" => Ecto.UUID.generate(),
        "turn_id" => Ecto.UUID.generate(),
        "report" => %{"outcome" => outcome, "summary" => summary(prompt["stage"], outcome)},
        "tools" => tools,
        "changes" => changes
      }

      if Process.get(:provider_failure_stage) == prompt["stage"] do
        Map.merge(receipt, %{
          "status" => "provider_error",
          "cleanup_verified" => Process.get(:provider_cleanup, true),
          "raw_provider" => "private-canary"
        })
      else
        receipt
      end
    end

    defp outcome(prompt) do
      cond do
        Process.get(:block_stage) == prompt["stage"] ->
          "blocked"

        first_review_rejected?(prompt) ->
          "changes_requested"

        Process.get(:invalid_outcome_stage) == prompt["stage"] ->
          "changes_requested"

        prompt["stage"] in ~w(secutor final_secutor) and
            Enum.any?(prompt["host_checks"] || [], &(&1["status"] != "passed")) ->
          "changes_requested"

        true ->
          "completed"
      end
    end

    defp first_review_rejected?(%{"stage" => "secutor", "review_round" => 0}),
      do: Process.get(:reject_first_review, false)

    defp first_review_rejected?(_), do: false

    defp summary("implementor", _), do: "Implemented the frozen criteria."

    defp summary(_, "changes_requested"),
      do: "Correct the failing declared check while retaining all criteria."

    defp summary(stage, _), do: "#{stage} public result."
    defp digest(value), do: Base.encode16(:crypto.hash(:sha, value), case: :lower)
    defp remember(key, value), do: Process.put(key, Process.get(key, []) ++ [value])
  end

  setup do
    previous = Application.get_env(:cuckoding, :data_dir)
    previous_home = Application.get_env(:cuckoding, :discovery_home)
    root = "/private/tmp/cuckoding-executor-test-#{Ecto.UUID.generate()}"
    source = Path.join(root, "source")
    File.mkdir_p!(source)
    File.write!(Path.join(source, "original.txt"), "Original checkout bytes\n")
    Application.put_env(:cuckoding, :data_dir, Path.join(root, "data"))
    Application.put_env(:cuckoding, :discovery_home, Path.join(root, "home"))
    Storage.prepare!(Path.join(root, "data"))

    on_exit(fn ->
      Application.put_env(:cuckoding, :data_dir, previous)
      Application.put_env(:cuckoding, :discovery_home, previous_home)
      File.rm_rf!(root)
    end)

    %{board: board, arena: arena} = Cuckoding.PlanningFixtures.planning_fixture()
    {:ok, folder} = Arenas.inspect_folder(source)

    Repo.update!(
      Ecto.Changeset.change(arena,
        path: folder["path"],
        device: folder["device"],
        inode: folder["inode"]
      )
    )

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
      "name" => "Fixture check",
      "executable" => "true",
      "arguments" => [],
      "directory" => ".",
      "timeout_seconds" => 20
    }

    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), board.arena_id, 0, [check], true)
    first = save_task(board, "First", [])
    second = save_task(board, "Second", [first.id])
    %{board: board, first: first, second: second, source: source, check: check}
  end

  defp save_task(board, title, dependencies) do
    {:ok, _} =
      Tabulae.save(Ecto.UUID.generate(), board.arena_id, board.id, Ecto.UUID.generate(), 0, %{
        "title" => title,
        "description" => "Implement #{title}",
        "criteria" => "Retain every #{title} criterion",
        "column" => "specs",
        "depends_on" => dependencies
      })

    Enum.find(Tabulae.tasks(board.id), &(&1.title == title))
  end

  defp start(board, now \\ DateTime.utc_now()) do
    {:ok, preview} = Battles.preview(board.arena_id, board.id)
    assert preview.blockers == []

    {:ok, battle} =
      Battles.start(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        preview.fingerprint,
        true,
        now
      )

    battle
  end

  defp step(battle) do
    {:ok, attempt} = Battles.claim_next(battle.id)
    result = BattleExecutor.execute(attempt, git: Adapters, provider: Adapters, checks: Adapters)
    assert {:ok, next} = Battles.finish(attempt.id, attempt.claim_token, result)
    {next, attempt, result}
  end

  defp drive(battle, remaining \\ 60)
  defp drive(%{state: state} = battle, _) when state in ~w(completed partial), do: battle

  defp drive(battle, remaining) when remaining > 0 do
    assert battle.state == "running", inspect(battle.reason)
    {battle, _, _} = step(battle)
    drive(battle, remaining - 1)
  end

  defp until_stage(battle, stage) do
    if battle.stage == stage, do: battle, else: until_stage(elem(step(battle), 0), stage)
  end

  defp closure_receipt(attempt) do
    ProviderClosure.binding_for(attempt)
    |> Map.take(~w(attempt_sha256 agent_id kind))
    |> Map.merge(%{
      "status" => "provider_closed",
      "request_id" => attempt.id,
      "cleanup_verified" => true,
      "pid" => 123,
      "spawned_at_ms" => 1000,
      "elapsed_ms" => 20,
      "receipt_sha256" => String.duplicate("a", 64)
    })
  end

  test "custom roles use real executor read grants and pass ordered findings to Implementor",
       ctx do
    old = TeamAssignments.assigned(ctx.board)

    role =
      Team.custom_role()
      |> Map.merge(%{"name" => "Research", "agent" => "codex", "model_id" => "test-id"})

    {:ok, team} =
      Team.save(Ecto.UUID.generate(), old.id, Team.editable(old) ++ [role], false, ctx.board)

    custom = %{
      "key" => "step_" <> Ecto.UUID.generate(),
      "name" => "Research",
      "role" => role["id"]
    }

    {:ok, _} =
      Cuckoding.Workflows.configure(
        Ecto.UUID.generate(),
        ctx.board.arena_id,
        ctx.board.id,
        0,
        team.id,
        Cuckoding.Workflows.labels(ctx.board.definition),
        [custom]
      )

    battle = start(ctx.board) |> until_stage(custom["key"])
    {next, attempt, receipt} = step(battle)
    assert attempt.role == role["id"]
    assert receipt["provider"]["access"] == "read"
    assert receipt["provider"]["changes"] == []
    {_, writer, _} = step(next)
    assert writer.stage == "implementor"
    calls = Process.get(:provider_calls)

    {prompt, request, _} =
      Enum.find(calls, fn {prompt, _, _} -> prompt["stage"] == custom["key"] end)

    assert request["access"] == "read" and prompt["instruction"] =~ "512"
    {writing, _, _} = Enum.find(calls, fn {prompt, _, _} -> prompt["stage"] == "implementor" end)
    assert [%{"stage" => stage, "summary" => summary}] = writing["workflow_findings"]
    assert stage == custom["key"] and summary == receipt["provider"]["report"]["summary"]
    assert writing["prior_public_summary"] != summary
    assert drive(Battles.get(battle.id)).state == "completed"
  end

  test "executor checks and independently reviews the combined wave candidate before integration",
       ctx do
    independent = save_task(ctx.board, "Independent", [])

    completed =
      Enum.reduce_while(1..100, start(ctx.board), fn _, battle ->
        {next, _, _} = step(battle)
        if next.state == "completed", do: {:halt, next}, else: {:cont, next}
      end)

    assert completed.state == "completed"
    history = Battles.attempts(completed.id)
    combined = Enum.find(history, &(&1.stage == "combine"))
    assert combined.task_id == independent.id
    review = Enum.find(history, &(&1.task_id == independent.id and &1.stage == "secutor"))
    assert review.request["task_context"]["candidate_sha"] == combined.result["candidate_sha"]
    checks = Enum.find(history, &(&1.task_id == independent.id and &1.stage == "checks"))
    assert checks.result["candidate_sha"] == combined.result["candidate_sha"]
    integrated = Enum.find(history, &(&1.task_id == independent.id and &1.stage == "integrate"))
    assert integrated.result["head"] == combined.result["candidate_sha"]
  end

  test "retained provider closure permits Stop without accepting the interrupted turn", ctx do
    battle = start(ctx.board) |> until_stage("implementor")
    {:ok, attempt} = Battles.claim_next(battle.id)
    assert attempt.request["snapshot"]["provider_closure"] == ProviderClosure.policy()
    assert {:ok, _} = Battles.recover()
    interrupted = Repo.get!(Attempt, attempt.id)
    before = Battles.get(battle.id)
    tasks = Battles.tasks(battle.id)
    assert Battles.recovery_attempt() == interrupted
    assert {:error, :cleanup_required} = Battles.stop(battle.id)

    result =
      BattleExecutor.reconcile_provider(interrupted, fn exact, active? ->
        assert exact == interrupted
        assert active?.()
        closure_receipt(exact)
      end)

    assert {:ok, observed} = Battles.reconcile_provider(interrupted, result)
    assert observed.state == "needs_attention"
    assert observed.context["head"] == before.context["head"]
    assert observed.turns_used == before.turns_used
    assert observed.deadline_at == before.deadline_at
    assert observed.stage == before.stage
    assert Battles.tasks(battle.id) == tasks
    assert Repo.get!(Attempt, attempt.id) == interrupted
    assert Battles.recovery_attempt() == nil
    assert {:error, :stale_reconciliation} = Battles.reconcile_provider(interrupted, result)
    refute match?({:ok, _}, Battles.resume(observed.id, observed.control_revision))
    refute match?({:ok, _}, Battles.retry(observed.id, observed.control_revision))

    refute match?(
             {:ok, _},
             Battles.skip(observed.id, observed.control_revision, ctx.first.id, true)
           )

    assert {:ok, _} = Battles.recover()
    assert Repo.get!(Attempt, attempt.id) == interrupted
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
  end

  test "provider recovery rejects changed, malformed and foreign closure with no fallback", ctx do
    battle = start(ctx.board) |> until_stage("coordinator")
    {:ok, attempt} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.recover()
    interrupted = Repo.get!(Attempt, attempt.id)
    receipt = closure_receipt(interrupted)
    assert receipt["attempt_sha256"] == Snapshot.digest(attempt.request)
    result = BattleExecutor.reconcile_provider(interrupted, fn _, _ -> receipt end)

    for invalid <- [
          put_in(result, ["provider_closure", "request_id"], Ecto.UUID.generate()),
          put_in(result, ["provider_closure", "attempt_sha256"], String.duplicate("b", 64)),
          put_in(result, ["provider_closure", "agent_id"], Ecto.UUID.generate()),
          put_in(result, ["provider_closure", "cleanup_verified"], "true"),
          Map.put(result, "summary", "Do not accept this work")
        ] do
      assert {:error, :invalid_result} = Battles.reconcile_provider(interrupted, invalid)
      assert Battles.provider_reconciliation_current?(interrupted)
    end

    failure =
      BattleExecutor.reconcile_provider(interrupted, fn _, _ ->
        %{"status" => "closure_unavailable"}
      end)

    assert {:ok, failed} = Battles.reconcile_provider(interrupted, failure)
    refute failed.context["provider_closure_pending"]
    assert {:error, :cleanup_required} = Battles.stop(failed.id)
    assert Repo.get!(Attempt, attempt.id) == interrupted
  end

  test "provider closure commits in its supervised worker before a lost coordinator notification",
       ctx do
    battle = start(ctx.board) |> until_stage("implementor")
    {:ok, attempt} = Battles.claim_next(battle.id)
    parent = self()

    reconciler = fn interrupted ->
      send(parent, {:closing_provider, self(), interrupted})

      receive do
        :inspect ->
          BattleExecutor.reconcile_provider(interrupted, fn _, active? ->
            assert active?.()
            closure_receipt(interrupted)
          end)
      end
    end

    executor = fn next ->
      send(parent, {:unexpected_provider_replay, next})
      exit(:shutdown)
    end

    start_supervised!(
      {Cuckoding.ExecutionSupervisor,
       coordinator: BattleRunner,
       tasks: Cuckoding.BattleTasks,
       options: [executor: executor, reconciler: reconciler]}
    )

    runner = Process.whereis(BattleRunner)
    assert_receive {:closing_provider, worker, interrupted}, 1000
    assert interrupted.id == attempt.id
    assert worker != runner
    assert worker in Task.Supervisor.children(Cuckoding.BattleTasks)
    :sys.suspend(runner)
    monitor = Process.monitor(worker)
    send(worker, :inspect)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1000
    observed = Battles.get(battle.id)
    assert observed.context["provider_closures"][attempt.id]["cleanup_verified"] == true
    assert Repo.get!(Attempt, attempt.id) == interrupted
    Process.exit(runner, :kill)

    await(fn ->
      is_pid(Process.whereis(BattleRunner)) and Process.whereis(BattleRunner) != runner
    end)

    assert Battles.get(battle.id) == observed
    refute_receive {:closing_provider, _, _}, 100
    refute_receive {:unexpected_provider_replay, _}, 100

    assert Enum.count(
             Battles.evidence(battle.id),
             &(&1.kind == "battle.provider_closure_observed")
           ) == 1

    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
  end

  test "Skip retains failed edits and reviews only independent work on the reviewed head", ctx do
    independent = save_task(ctx.board, "Independent", [])
    battle = start(ctx.board) |> until_stage("implementor")
    old_preparation = hd(Battles.tasks(battle.id)).context["preparation"]
    Process.put(:provider_failure_stage, "implementor")
    {failed, attempt, receipt} = step(battle)
    Process.delete(:provider_failure_stage)
    {:ok, skipped} = Battles.skip(failed.id, 0, ctx.first.id, true)
    partial = drive(skipped)
    assert partial.state == "partial"
    assert Repo.get!(Attempt, attempt.id).result == receipt
    assert receipt["provider"]["changes"] != []
    assert hd(Battles.tasks(battle.id)).context["preparation"] == old_preparation
    independent_task = Enum.find(Battles.tasks(battle.id), &(&1.task_id == independent.id))
    assert independent_task.state == "completed"
    refute independent_task.context["preparation"]["key"] == old_preparation["key"]
    assert independent_task.context["preparation"]["head"] == battle.context["head"]
    assert File.read!(Path.join(ctx.source, "original.txt")) == "Original checkout bytes\n"

    for {prompt, request, _} <- Process.get(:provider_calls),
        prompt["stage"] in ~w(final_secutor summary) do
      assert Enum.map(prompt["task"], & &1["id"]) == [independent.id]
      assert prompt["result_scope"] == "partial"

      assert prompt["omitted_tasks"] == [
               %{"id" => ctx.first.id, "state" => "skipped"},
               %{"id" => ctx.second.id, "state" => "deferred"}
             ]

      assert request["access"] == "read"
    end

    assert Enum.map(Process.get(:check_calls), &elem(&1, 0)) == ["checks", "final_checks"]
    assert length(Enum.filter(Battles.attempts(battle.id), &(&1.stage == "integrate"))) == 1
  end

  test "partial scope still blocks on missing final evidence", ctx do
    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), ctx.board.arena_id, 1, [], true)
    battle = start(ctx.board) |> until_stage("integrate")
    {battle, _, _} = step(battle)
    {:ok, paused} = Battles.pause(battle.id, 0)
    {:ok, skipped} = Battles.skip(paused.id, 1, ctx.second.id, true)
    {:ok, resumed} = Battles.resume(skipped.id, 2)
    Process.put(:block_stage, "final_secutor")
    {blocked, _, _} = step(resumed)
    assert blocked.state == "needs_attention"
    assert blocked.stage == "final_secutor"
    assert Battles.skip_preview(blocked) == []

    refute Enum.any?(
             Battles.evidence(battle.id),
             &(&1.kind in ~w(battle.partial battle.completed))
           )
  end

  test "Retry retains failed writer effects and completes through a different workspace", ctx do
    battle = start(ctx.board) |> until_stage("implementor")
    old_preparation = hd(Battles.tasks(battle.id)).context["preparation"]
    Process.put(:provider_failure_stage, "implementor")
    {failed, attempt, receipt} = step(battle)
    assert failed.state == "needs_attention"

    assert receipt["provider"]["changes"] == [
             %{"path" => "feature.txt", "sha256" => String.duplicate("d", 64)}
           ]

    refute receipt["provider"]["raw_provider"]
    refute receipt["provider"]["report"]
    Process.delete(:provider_failure_stage)
    {:ok, retried} = Battles.retry(failed.id, 0)
    completed = drive(retried)
    assert completed.state == "completed"
    assert completed.deadline_at == battle.deadline_at
    assert Repo.get!(Attempt, attempt.id).result == receipt
    new_preparation = hd(Battles.tasks(battle.id)).context["preparation"]
    refute new_preparation["key"] == old_preparation["key"]
    assert new_preparation["head"] == old_preparation["head"]
    assert File.read!(Path.join(ctx.source, "original.txt")) == "Original checkout bytes\n"

    writes =
      Process.get(:provider_calls)
      |> Enum.filter(fn {_, request, _} -> request["access"] == "write" end)

    assert length(writes) == 3
  end

  test "provider cleanup refusal preserves partial effects and cannot be retried", ctx do
    battle = start(ctx.board) |> until_stage("implementor")
    Process.put(:provider_failure_stage, "implementor")
    Process.put(:provider_cleanup, false)
    {failed, _, receipt} = step(battle)
    assert receipt["cleanup_verified"] == false
    assert receipt["reason"] == "cleanup_uncertain"
    assert length(receipt["provider"]["changes"]) == 1
    refute Battles.retry_available?(failed)
    assert {:error, :retry_unavailable} = Battles.retry(failed.id, 0)
    assert {:error, :cleanup_required} = Battles.stop(failed.id)
    assert Battles.get(failed.id).state == "needs_attention"
  end

  test "final Secutor and summary share a finite retry allowance and preserve review", ctx do
    battle = start(ctx.board) |> until_stage("final_secutor")
    Process.put(:provider_failure_stage, "final_secutor")
    {failed, _, _} = step(battle)
    {:ok, retried} = Battles.retry(failed.id, 0)
    Process.put(:provider_failure_stage, "summary")
    {reviewed, _, _} = step(retried)
    assert reviewed.stage == "summary"
    {failed, _, _} = step(reviewed)
    {:ok, retried} = Battles.retry(failed.id, 1)
    {exhausted, _, _} = step(retried)
    refute Battles.retry_available?(exhausted)
    assert {:error, :retry_unavailable} = Battles.retry(exhausted.id, 2)
    assert Enum.count(Battles.attempts(battle.id), &(&1.stage == "final_secutor")) == 2
    assert Enum.all?(Battles.tasks(battle.id), &(&1.state == "completed"))
    refute exhausted.state == "completed"
  end

  test "mixed Cursor and Codex roles retain exact bindings through review and completion", ctx do
    assert BattleExecutor.provider_for("cursor") == Cursor
    assert BattleExecutor.provider_for("codex") == Codex

    {:ok, command} =
      Agents.add_and_probe(
        Ecto.UUID.generate(),
        Foundation.workspace().revision,
        "Cursor fixture",
        "cursor",
        "/bin/sh"
      )

    {:ok, claim} = Foundation.claim()

    {:ok, _} =
      Foundation.finish(claim, %{"status" => "supported", "version" => Cursor.task_version()})

    id = command.payload["agent_id"]

    {:ok, _} =
      Foundation.inspect_codex(Ecto.UUID.generate(), Foundation.workspace().revision, true, id)

    {:ok, claim} = Foundation.claim()

    {:ok, _} =
      Foundation.finish(claim, %{
        "status" => "checked",
        "authorization" => "cursor",
        "catalog_status" => "fresh",
        "models" => [
          %{
            "id" => "cursor-test",
            "model" => "cursor-test",
            "name" => "Cursor fixture model",
            "default" => true,
            "hidden" => false
          }
        ]
      })

    {:ok, _} =
      Foundation.save_agent_models(
        Ecto.UUID.generate(),
        Foundation.workspace().revision,
        Agents.get(id).connection["command_id"],
        ["cursor-test"],
        id
      )

    team = Team.current()

    roles =
      Enum.map(Team.editable(team), fn role ->
        if role["id"] in ~w(implementor summa_rudis),
          do: Map.merge(role, %{"agent" => id, "model_id" => "cursor-test"}),
          else: role
      end)

    {:ok, team} = Team.save(Ecto.UUID.generate(), team.id, roles)
    board = Tabulae.get(ctx.board.arena_id, ctx.board.id)

    {:ok, _} =
      TeamAssignments.adopt(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        TeamAssignments.assigned(board).id,
        team.id,
        true
      )

    {:ok, blocked} = Battles.preview(board.arena_id, board.id)
    assert "check_runtime_required" in blocked.blockers
    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), board.arena_id, 1, [], true)
    Process.put(:reject_first_review, true)
    battle = board |> start() |> drive()
    assert battle.state == "completed"
    assert Enum.all?(Battles.tasks(battle.id), &(&1.review_round == 1))
    assert Process.get(:check_calls, []) == []

    for attempt <- Battles.attempts(battle.id), attempt.request["role"] do
      role = attempt.request["role"]
      cursor? = role["id"] in ~w(implementor summa_rudis)
      assert role["agent_id"] == if(cursor?, do: id, else: "codex")

      assert attempt.result["provider"]["requested_model"] ==
               if(cursor?, do: "cursor-test", else: "test-model")
    end
  end

  test "task checks need no command configuration, survive corrections and receive a final review",
       ctx do
    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), ctx.board.arena_id, 1, [], true)
    Process.put(:reject_first_review, true)
    battle = ctx.board |> start() |> drive()
    assert battle.state == "completed"
    assert Process.get(:check_calls, []) == []
    attempts = Battles.attempts(battle.id)
    refute Enum.any?(attempts, &(&1.stage in ~w(checks final_checks)))
    assert Enum.all?(Battles.tasks(battle.id), &(&1.review_round == 1))
    providers = Process.get(:provider_calls)

    {correction, _, _} =
      Enum.find(providers, fn {p, _, _} ->
        p["stage"] == "speculator" and p["review_round"] == 1
      end)

    assert correction["task"]["criteria"] == ctx.first.criteria
    assert correction["review_findings"] != nil
    {review, request, _} = Enum.find(providers, fn {p, _, _} -> p["stage"] == "final_secutor" end)
    assert Enum.map(review["task"], & &1["criteria"]) == [ctx.first.criteria, ctx.second.criteria]
    assert review["command_check_scope"] == "not_configured"
    assert review["host_checks"] == nil
    assert review["declared_checks"] == []
    assert review["instruction"] =~ "blocked for missing runtime/test evidence"
    assert request["access"] == "read"
    assert request["workspace"]["head"] == battle.context["head"]
    refute Enum.any?(attempts, &Map.has_key?(&1.result, "checks"))
  end

  test "missing required task evidence blocks completion without extra command configuration",
       ctx do
    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), ctx.board.arena_id, 1, [], true)
    Process.put(:block_stage, "secutor")
    battle = ctx.board |> start() |> until_stage("secutor")
    {battle, _, receipt} = step(battle)
    assert receipt["status"] == "blocked"
    assert battle.state == "needs_attention"
    refute Enum.any?(Battles.tasks(battle.id), &(&1.state == "completed"))
    refute Enum.any?(Battles.attempts(battle.id), &(&1.stage == "integrate"))
  end

  test "two dependent tasks correct failed checks and finish with an independent combined review",
       ctx do
    Process.put(:fail_first_check, true)
    battle = ctx.board |> start() |> drive()
    attempts = Battles.attempts(battle.id)
    assert battle.state == "completed"

    assert Enum.map(Battles.tasks(battle.id), &{&1.task_id, &1.state, &1.review_round}) == [
             {ctx.first.id, "completed", 1},
             {ctx.second.id, "completed", 0}
           ]

    assert Enum.count(attempts, &(&1.stage == "prepare_worktree")) == 3
    assert Enum.count(attempts, &(&1.stage == "integrate")) == 2
    assert Enum.any?(attempts, &(&1.stage == "checks" and &1.result["status"] == "checks_failed"))
    assert Enum.map(Enum.take(attempts, -3), & &1.stage) == ~w(final_checks final_secutor summary)

    first_integration =
      Enum.find(attempts, &(&1.stage == "integrate" and &1.task_id == ctx.first.id))

    second_preparation =
      Enum.find(attempts, &(&1.stage == "prepare_worktree" and &1.task_id == ctx.second.id))

    assert second_preparation.request["context"]["head"] == first_integration.result["head"]
    providers = Process.get(:provider_calls)

    {correction, _, _} =
      Enum.find(providers, fn {prompt, _, _} ->
        prompt["stage"] == "speculator" and prompt["review_round"] == 1
      end)

    assert correction["review_findings"] =~ "failing declared check"
    assert correction["previous_implementation"] == "Implemented the frozen criteria."
    assert correction["task"]["criteria"] == ctx.first.criteria

    {final_review, final_request, _} =
      Enum.find(providers, fn {prompt, _, _} -> prompt["stage"] == "final_secutor" end)

    assert Enum.map(final_review["task"], & &1["criteria"]) == [
             ctx.first.criteria,
             ctx.second.criteria
           ]

    assert final_review["declared_checks"] == [ctx.check]
    assert final_request["access"] == "read"
    assert final_request["workspace"]["head"] == battle.context["head"]

    writable_keys =
      for {_, request, _} <- providers,
          request["access"] == "write",
          do: request["workspace"]["key"]

    review_keys =
      for {prompt, request, _} <- providers,
          prompt["stage"] in ~w(secutor final_secutor),
          do: request["workspace"]["key"]

    assert MapSet.disjoint?(MapSet.new(writable_keys), MapSet.new(review_keys))
    assert File.read!(Path.join(ctx.source, "original.txt")) == "Original checkout bytes\n"
  end

  test "non-review changes_requested becomes an explicit failure without a stuck claim", %{
    board: board
  } do
    Process.put(:invalid_outcome_stage, "coordinator")
    battle = board |> start() |> until_stage("coordinator")
    {battle, attempt, result} = step(battle)
    assert result["status"] == "failed"
    assert result["reason"] == "invalid_role_outcome"
    assert battle.state == "needs_attention"
    assert Repo.get!(Attempt, attempt.id).state == "failed"
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
  end

  test "model drift is retained as failure and cannot reach candidate capture", %{board: board} do
    battle = board |> start() |> until_stage("implementor")
    Process.put(:observed_model, "different-model")
    {battle, _, result} = step(battle)
    assert battle.state == "needs_attention"
    assert result["reason"] == "model_or_grant_changed"

    refute Enum.any?(Process.get(:git_calls), fn {operation, _, _} ->
             operation == "capture_candidate"
           end)
  end

  test "active frozen drafts reject edits while unrelated new drafts remain writable", %{
    board: board,
    first: first
  } do
    battle = start(board)
    attrs = Map.put(Tabulae.content(first), "criteria", "Changed after Start")

    assert {:error, "battle_active"} =
             Tabulae.save(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               first.id,
               first.revision,
               attrs
             )

    later = save_task(board, "Later", [])
    refute Enum.any?(battle.snapshot["tasks"], &(&1["id"] == later.id))
    assert Enum.find(Tabulae.tasks(board.id), &(&1.id == first.id)).criteria == first.criteria
  end

  test "executor cancellation after expiry retains cleanup and closes without dispatch", ctx do
    before_deadline = DateTime.add(DateTime.utc_now(), -7201)
    battle = start(ctx.board, before_deadline)
    {:ok, attempt} = Battles.claim_next(battle.id, before_deadline)
    receipt = BattleExecutor.execute(attempt, git: Adapters, checks: Adapters, provider: Adapters)
    assert receipt["status"] == "cancelled"
    assert receipt["cleanup_verified"] == true
    assert Process.get(:git_calls, []) == []
    assert Process.get(:provider_calls, []) == []

    assert {:error, "late_result_rejected"} =
             Battles.finish(attempt.id, attempt.claim_token, receipt)

    expired = Repo.get!(Attempt, attempt.id)
    assert expired.state == "expired"
    assert expired.result == receipt
    {:ok, stopped} = Battles.stop(battle.id)
    assert stopped.state == "stopped"
    assert Repo.get!(Attempt, attempt.id) == expired
  end

  test "automatic backoff releases its worker and dispatches a fresh attempt when due", ctx do
    parent = self()

    executor = fn attempt ->
      cond do
        attempt.stage != "coordinator" ->
          BattleExecutor.execute(attempt, git: Adapters, checks: Adapters, provider: Adapters)

        is_nil(attempt.request["context"]["provider_retries"]) ->
          Map.merge(
            Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256)),
            %{
              "status" => "failed",
              "reason" => "connection_lost",
              "provider" => %{"status" => "connection_lost"},
              "cleanup_verified" => true
            }
          )

        true ->
          send(parent, {:backoff_launched, self(), attempt})

          receive do
            :finish ->
              BattleExecutor.execute(attempt, git: Adapters, checks: Adapters, provider: Adapters)
          end
      end
    end

    start_supervised!(
      {Cuckoding.ExecutionSupervisor,
       coordinator: BattleRunner, tasks: Cuckoding.BattleTasks, options: [executor: executor]}
    )

    battle = start(ctx.board)
    runner = Process.whereis(BattleRunner)
    send(runner, :poll)
    await(fn -> Backoff.pending?(Battles.get(battle.id)) end)
    await(fn -> :sys.get_state(runner).jobs == %{} end)
    assert Task.Supervisor.children(Cuckoding.BattleTasks) == []
    failed = List.last(Battles.attempts(battle.id))
    refute_receive {:backoff_launched, _, _}, 50
    assert_receive {:backoff_launched, worker, attempt}, 6_000
    assert attempt.id != failed.id
    assert attempt.request["context"]["provider_retries"] == [failed.id]
    assert Repo.get!(Attempt, failed.id) == failed
    current = Battles.get(battle.id)
    {:ok, _} = Battles.pause(battle.id, current.control_revision)
    send(worker, :finish)
    await(fn -> Battles.get(battle.id).state == "paused" end)
  end

  test "runner records invalid receipt failure and closes admission without replay", %{
    board: board
  } do
    unless Process.whereis(Cuckoding.BattleTasks),
      do: start_battle_tasks()

    test = self()

    executor = fn attempt ->
      send(test, {:stage_launched, attempt.id})
      %{"status" => "admitted", "cleanup_verified" => true}
    end

    runner = start_supervised!({BattleRunner, executor: executor})
    battle = start(board)
    send(runner, :poll)
    assert_receive {:stage_launched, attempt_id}, 1000
    await(fn -> Battles.get(battle.id).state == "needs_attention" end)
    assert Battles.get(battle.id).reason == "invalid_stage_receipt"
    attempt = Repo.get!(Attempt, attempt_id)
    assert attempt.state == "failed"
    assert attempt.result["cleanup_verified"] == false
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    send(runner, :poll)
    refute_receive {:stage_launched, _}, 100
    assert length(Battles.attempts(battle.id)) == 1
  end

  test "committed stage survives a crash with its completion notification still queued", ctx do
    parent = self()

    executor = fn attempt ->
      send(parent, {:handoff_stage, self(), attempt})

      receive do
        :finish ->
          BattleExecutor.execute(attempt, git: Adapters, checks: Adapters, provider: Adapters)
      end
    end

    start_supervised!(
      {Cuckoding.ExecutionSupervisor,
       coordinator: BattleRunner, tasks: Cuckoding.BattleTasks, options: [executor: executor]}
    )

    battle = start(ctx.board)
    runner = Process.whereis(BattleRunner)
    send(runner, :poll)
    assert_receive {:handoff_stage, worker, attempt}, 1_000
    :sys.suspend(runner)
    monitor = Process.monitor(worker)
    send(worker, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
    receipt = Repo.get!(Attempt, attempt.id)
    assert receipt.state == "completed"
    assert Battles.get(battle.id).stage == "prepare_worktree"
    Process.exit(runner, :kill)
    await(fn -> Battles.get(battle.id).state == "paused" end)
    recovered = Battles.get(battle.id)
    assert recovered.reason == "restart_checkpoint"
    assert recovered.stage == "prepare_worktree"
    assert recovered.snapshot == battle.snapshot
    assert recovered.deadline_at == battle.deadline_at
    assert Repo.get!(Attempt, attempt.id) == receipt
    assert length(Battles.attempts(battle.id)) == 1
    refute_receive {:handoff_stage, _, _}, 100

    {:ok, resumed} = Battles.resume(battle.id, recovered.control_revision)
    send(Process.whereis(BattleRunner), :poll)
    assert_receive {:handoff_stage, next_worker, next}, 1_000
    assert next.stage == "prepare_worktree"
    refute next.id == attempt.id
    {:ok, _} = Battles.pause(battle.id, resumed.control_revision)
    send(next_worker, :finish)
    await(fn -> Battles.get(battle.id).state == "paused" end)
    assert length(Battles.attempts(battle.id)) == 2
  end

  test "committed failure stays immutable when its coordinator crashes before notification",
       ctx do
    parent = self()

    executor = fn attempt ->
      send(parent, {:failed_handoff, self(), attempt})

      receive do
        :finish ->
          Map.merge(
            Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256)),
            %{"status" => "failed", "reason" => "provider_error", "cleanup_verified" => true}
          )
      end
    end

    start_supervised!(
      {Cuckoding.ExecutionSupervisor,
       coordinator: BattleRunner, tasks: Cuckoding.BattleTasks, options: [executor: executor]}
    )

    battle = start(ctx.board)
    runner = Process.whereis(BattleRunner)
    send(runner, :poll)
    assert_receive {:failed_handoff, worker, attempt}, 1_000
    :sys.suspend(runner)
    monitor = Process.monitor(worker)
    send(worker, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
    receipt = Repo.get!(Attempt, attempt.id)
    assert receipt.state == "failed"
    failed = Battles.get(battle.id)
    assert failed.state == "needs_attention"
    assert failed.reason == "provider_error"
    Process.exit(runner, :kill)

    await(fn ->
      is_pid(Process.whereis(BattleRunner)) and Process.whereis(BattleRunner) != runner
    end)

    assert Battles.get(battle.id) == failed
    assert Repo.get!(Attempt, attempt.id) == receipt
    assert length(Battles.attempts(battle.id)) == 1
    refute_receive {:failed_handoff, _, _}, 100
  end

  test "a worker exception preserves uncertainty without logging private provider text", ctx do
    parent = self()

    executor = fn attempt ->
      send(parent, {:crashing_stage, attempt.id})
      raise "private-provider-error-canary"
    end

    start_supervised!(
      {Cuckoding.ExecutionSupervisor,
       coordinator: BattleRunner, tasks: Cuckoding.BattleTasks, options: [executor: executor]}
    )

    runner = Process.whereis(BattleRunner)
    battle = start(ctx.board)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        send(runner, :poll)
        await(fn -> Battles.get(battle.id).state == "needs_attention" end)
      end)

    assert_receive {:crashing_stage, attempt_id}, 1_000
    refute log =~ "private-provider-error-canary"
    assert Process.whereis(BattleRunner) == runner
    assert Battles.get(battle.id).reason == "worker_interrupted"
    assert Repo.get!(Attempt, attempt_id).result["cleanup_verified"] == false
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    refute_receive {:crashing_stage, _}, 100
  end

  test "Stop racing a validated finished stage retains verified cleanup without accepting work",
       ctx do
    assert_stop_handoff(ctx, :valid)
  end

  test "Stop cannot trust a cleanup flag from a bound but malformed stage receipt", ctx do
    assert_stop_handoff(ctx, :malformed)
  end

  test "coordinator restart stops its stage worker and retains uncertain work without replay",
       ctx do
    parent = self()

    executor = fn attempt ->
      send(parent, {:owned_stage, self(), attempt})

      receive do
        :finish ->
          BattleExecutor.execute(attempt, git: Adapters, checks: Adapters, provider: Adapters)
      end
    end

    start_supervised!(
      {Cuckoding.ExecutionSupervisor,
       coordinator: BattleRunner, tasks: Cuckoding.BattleTasks, options: [executor: executor]}
    )

    battle = start(ctx.board)
    runner = Process.whereis(BattleRunner)
    send(runner, :poll)
    assert_receive {:owned_stage, worker, attempt}, 1_000
    monitor = Process.monitor(worker)
    Process.exit(runner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :shutdown}, 1_000
    await(fn -> Battles.get(battle.id).state == "needs_attention" end)
    assert Battles.get(battle.id).reason == "restart_requires_inspection"
    assert Repo.get!(Attempt, attempt.id).state == "interrupted"
    assert Repo.get!(Attempt, attempt.id).result == %{"status" => "interrupted"}
    assert length(Battles.attempts(battle.id)) == 1
    assert Task.Supervisor.children(Cuckoding.BattleTasks) == []
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    refute_receive {:owned_stage, _, _}, 100
  end

  test "runner settles a pausing stage once and survives restart at the paused boundary", %{
    board: board
  } do
    start_battle_tasks()
    test = self()

    executor = fn attempt ->
      send(test, {:stage_started, self(), attempt})

      receive do
        :finish ->
          BattleExecutor.execute(attempt, git: Adapters, checks: Adapters, provider: Adapters)
      end
    end

    runner = start_supervised!({BattleRunner, executor: executor})
    battle = start(board)
    send(runner, :poll)
    assert_receive {:stage_started, worker, attempt}, 1000
    assert attempt.stage == "admission"
    {:ok, _} = Battles.pause(battle.id, 0)
    send(worker, :finish)
    await(fn -> Battles.get(battle.id).state == "paused" end)
    assert length(Battles.attempts(battle.id)) == 1
    refute_receive {:stage_started, _, _}, 100
    stop_supervised!(BattleRunner)
    runner = start_supervised!({BattleRunner, executor: executor})
    refute_receive {:stage_started, _, _}, 100
    assert Battles.get(battle.id).state == "paused"
    {:ok, _} = Battles.resume(battle.id, 1)
    send(runner, :poll)
    assert_receive {:stage_started, worker, attempt}, 1000
    assert attempt.stage == "prepare_worktree"
    {:ok, _} = Battles.pause(battle.id, 2)
    send(worker, :finish)
    await(fn -> Battles.get(battle.id).state == "paused" end)
    assert length(Battles.attempts(battle.id)) == 2
    assert Battles.get(battle.id).deadline_at == battle.deadline_at
  end

  test "runner restart holds a settled failure until explicit Retry and dispatches once", ctx do
    battle = start(ctx.board) |> until_stage("speculator")
    Process.put(:provider_failure_stage, "speculator")
    {failed, previous, _} = step(battle)
    start_battle_tasks()
    parent = self()

    executor = fn attempt ->
      send(parent, {:retry_stage, self(), attempt})

      receive do
        :finish ->
          BattleExecutor.execute(attempt, git: Adapters, provider: Adapters, checks: Adapters)
      end
    end

    start_supervised!({BattleRunner, executor: executor})
    refute_receive {:retry_stage, _, _}, 100
    stop_supervised!(BattleRunner)
    runner = start_supervised!({BattleRunner, executor: executor})
    refute_receive {:retry_stage, _, _}, 100
    {:ok, retried} = Battles.retry(failed.id, 0)
    send(runner, :poll)
    assert_receive {:retry_stage, worker, attempt}, 1000
    refute attempt.id == previous.id
    assert attempt.stage == previous.stage
    {:ok, _} = Battles.pause(retried.id, retried.control_revision)
    send(worker, :finish)
    await(fn -> Battles.get(battle.id).state == "paused" end)
    refute_receive {:retry_stage, _, _}, 100
    assert Repo.get!(Attempt, previous.id).state == "failed"
  end

  test "runner startup holds a completed checkpoint until explicit Resume", ctx do
    battle = start(ctx.board) |> until_stage("implementor")
    previous = Battles.attempts(battle.id)
    start_battle_tasks()
    parent = self()

    executor = fn attempt ->
      send(parent, {:checkpoint_stage, self(), attempt})

      receive do
        :finish ->
          BattleExecutor.execute(attempt, git: Adapters, provider: Adapters, checks: Adapters)
      end
    end

    runner = start_supervised!({BattleRunner, executor: executor})
    recovered = Battles.get(battle.id)
    assert recovered.state == "paused"
    assert recovered.reason == "restart_checkpoint"
    send(runner, :poll)
    refute_receive {:checkpoint_stage, _, _}, 100
    assert Battles.attempts(battle.id) == previous
    stop_supervised!(BattleRunner)
    runner = start_supervised!({BattleRunner, executor: executor})
    assert Battles.get(battle.id) == recovered
    {:ok, resumed} = Battles.resume(battle.id, recovered.control_revision)
    send(runner, :poll)
    assert_receive {:checkpoint_stage, worker, attempt}, 1000
    assert attempt.stage == "implementor"
    assert attempt.request["task_context"] == hd(Battles.tasks(battle.id)).context
    {:ok, _} = Battles.pause(battle.id, resumed.control_revision)
    send(worker, :finish)
    await(fn -> Battles.get(battle.id).state == "paused" end)
    assert Battles.get(battle.id).stage == "capture"
    assert length(Battles.attempts(battle.id)) == length(previous) + 1
    refute_receive {:checkpoint_stage, _, _}, 100
  end

  defp assert_stop_handoff(ctx, kind) do
    parent = self()

    executor = fn attempt ->
      result =
        BattleExecutor.execute(attempt, git: Adapters, checks: Adapters, provider: Adapters)

      result =
        if kind == :malformed, do: Map.drop(result, ["head", "native_battle"]), else: result

      send(parent, {:stop_handoff, self(), attempt})

      receive do
        :finish -> result
      end
    end

    start_supervised!(
      {Cuckoding.ExecutionSupervisor,
       coordinator: BattleRunner, tasks: Cuckoding.BattleTasks, options: [executor: executor]}
    )

    battle = start(ctx.board)
    send(Process.whereis(BattleRunner), :poll)
    assert_receive {:stop_handoff, worker, attempt}, 1_000
    {:ok, _} = Battles.stop(battle.id)
    send(worker, :finish)

    if kind == :valid do
      await(fn -> Battles.get(battle.id).state == "stopped" end)
      assert Repo.get!(Attempt, attempt.id).state == "cancelled"
      assert Repo.get!(Attempt, attempt.id).result["cleanup_verified"] == true
    else
      await(fn -> Battles.get(battle.id).state == "needs_attention" end)
      assert Battles.get(battle.id).reason == "cleanup_uncertain"
      assert Repo.get!(Attempt, attempt.id).result["cleanup_verified"] == false
      assert {:error, :cleanup_required} = Battles.stop(battle.id)
    end

    assert length(Battles.attempts(battle.id)) == 1
    assert Battles.get(battle.id).stage == "admission"
    refute_receive {:stop_handoff, _, _}, 100
  end

  test "startup reconciliation uses an async worker and survives a lost completion notification",
       ctx do
    battle = start(ctx.board) |> until_stage("integrate")
    {:ok, attempt} = Battles.claim_next(battle.id)
    parent = self()

    reconciler = fn interrupted ->
      send(parent, {:reconciling, self(), interrupted})

      receive do
        :inspect -> BattleExecutor.reconcile_integration(interrupted, git: Adapters)
      end
    end

    executor = fn next ->
      send(parent, {:unexpected_stage, next})
      raise "should remain paused"
    end

    start_supervised!(
      {Cuckoding.ExecutionSupervisor,
       coordinator: BattleRunner,
       tasks: Cuckoding.BattleTasks,
       options: [executor: executor, reconciler: reconciler]}
    )

    runner = Process.whereis(BattleRunner)
    assert_receive {:reconciling, worker, interrupted}, 1_000
    assert worker != runner
    assert worker in Task.Supervisor.children(Cuckoding.BattleTasks)
    assert interrupted.id == attempt.id
    assert interrupted.state == "interrupted"
    assert :sys.get_state(runner).jobs != %{}
    :sys.suspend(runner)
    monitor = Process.monitor(worker)
    send(worker, :inspect)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
    paused = Battles.get(battle.id)
    assert paused.state == "paused"
    assert paused.current_task_id == ctx.second.id
    assert paused.context["head"] == attempt.request["task_context"]["candidate_sha"]
    assert Repo.get!(Attempt, attempt.id) == interrupted
    Process.exit(runner, :kill)

    await(fn ->
      is_pid(Process.whereis(BattleRunner)) and Process.whereis(BattleRunner) != runner
    end)

    assert Battles.get(battle.id) == paused
    refute_receive {:reconciling, _, _}, 100
    refute_receive {:unexpected_stage, _}, 100
    {:ok, resumed} = Battles.resume(battle.id, paused.control_revision)
    assert resumed.snapshot == battle.snapshot
    assert resumed.deadline_at == battle.deadline_at
    {next, _, _} = step(resumed)
    assert next.stage == "coordinator"
    {:ok, _} = Battles.pause(battle.id, resumed.control_revision)
  end

  test "crashing during read-only reconciliation can repeat the observation without replaying integration",
       ctx do
    battle = start(ctx.board) |> until_stage("integrate")
    {:ok, attempt} = Battles.claim_next(battle.id)
    parent = self()

    reconciler = fn interrupted ->
      send(parent, {:reading_receipt, self(), interrupted})

      receive do
        :inspect -> BattleExecutor.reconcile_integration(interrupted, git: Adapters)
      end
    end

    start_supervised!(
      {Cuckoding.ExecutionSupervisor,
       coordinator: BattleRunner, tasks: Cuckoding.BattleTasks, options: [reconciler: reconciler]}
    )

    assert_receive {:reading_receipt, first_worker, interrupted}, 1_000
    monitor = Process.monitor(first_worker)
    Process.exit(Process.whereis(BattleRunner), :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first_worker, :shutdown}, 1_000
    assert_receive {:reading_receipt, next_worker, ^interrupted}, 1_000
    assert next_worker != first_worker
    assert Repo.get!(Attempt, attempt.id) == interrupted
    send(next_worker, :inspect)
    await(fn -> Battles.get(battle.id).state == "paused" end)

    assert Enum.count(Battles.evidence(battle.id), &(&1.kind == "battle.integration_reconciled")) ==
             1

    assert List.last(Battles.attempts(battle.id)).id == attempt.id
    assert Repo.get!(Attempt, attempt.id) == interrupted
    refute_receive {:reading_receipt, _, _}, 100
  end

  test "failed or malformed reconciliation runs once and keeps native cleanup uncertain", ctx do
    battle = start(ctx.board) |> until_stage("integrate")
    {:ok, attempt} = Battles.claim_next(battle.id)
    parent = self()

    reconciler = fn interrupted ->
      send(parent, {:reconciliation_called, interrupted.id})

      Map.merge(
        Map.take(interrupted.request, ~w(battle_id request_id task_id stage criteria_sha256)),
        %{
          "status" => "integrated",
          "head" => "forged",
          "candidate_sha" => "forged",
          "cleanup_verified" => true
        }
      )
    end

    start_supervised!(
      {Cuckoding.ExecutionSupervisor,
       coordinator: BattleRunner, tasks: Cuckoding.BattleTasks, options: [reconciler: reconciler]}
    )

    assert_receive {:reconciliation_called, id}, 1_000
    assert id == attempt.id
    await(fn -> is_nil(Battles.recovery_attempt()) end)
    attention = Battles.get(battle.id)
    assert attention.state == "needs_attention"
    observation = attention.context["integration_reconciliations"][attempt.id]
    assert observation["reason"] == "invalid_recovery_receipt"
    assert observation["cleanup_verified"] == false
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    refute_receive {:reconciliation_called, _}, 100
  end

  defp clocked_runner(executor) do
    clock = start_supervised!({Agent, fn -> {DateTime.utc_now(), 0} end})

    start_supervised!(
      {Cuckoding.ExecutionSupervisor,
       coordinator: BattleRunner,
       tasks: Cuckoding.BattleTasks,
       clock: [clock: fn -> Agent.get(clock, & &1) end],
       options: [executor: executor]}
    )

    {clock, Process.whereis(BattleRunner)}
  end

  defp move_clock(clock, wall, monotonic) do
    Agent.update(clock, fn {now, elapsed} ->
      {DateTime.add(now, wall, :millisecond), elapsed + monotonic}
    end)
  end

  test "independent clock fences admission while the coordinator is suspended", ctx do
    parent = self()

    {clock, runner} =
      clocked_runner(fn attempt -> send(parent, {:unexpected_admission, attempt.id}) end)

    :sys.suspend(runner)
    battle = start(ctx.board)
    move_clock(clock, 60_000, 1_000)
    :ok = Cuckoding.BattleClock.check()
    paused = Battles.get(battle.id)
    assert paused.state == "paused"
    assert paused.reason == "timing_gap"
    assert paused.snapshot == battle.snapshot
    assert paused.deadline_at == battle.deadline_at
    assert Battles.attempts(battle.id) == []
    :sys.resume(runner)
    send(runner, :poll)
    refute_receive {:unexpected_admission, _}, 100
    assert {:error, :stale_control} = Battles.resume(battle.id, battle.control_revision)

    assert {:error, "deadline_exceeded"} =
             Battles.resume(battle.id, paused.control_revision, battle.deadline_at)

    assert Battles.get(battle.id).deadline_at == battle.deadline_at
  end

  test "worker checks the clock before settlement without relying on its coordinator mailbox",
       ctx do
    parent = self()

    executor = fn attempt ->
      receipt =
        BattleExecutor.execute(attempt, git: Adapters, provider: Adapters, checks: Adapters)

      send(parent, {:timed_handoff, self(), attempt, receipt})

      receive do
        :finish -> receipt
      end
    end

    {clock, runner} = clocked_runner(executor)
    battle = start(ctx.board)
    send(runner, :poll)
    assert_receive {:timed_handoff, worker, attempt, receipt}, 1_000
    :sys.suspend(runner)
    move_clock(clock, 6_000, 6_000)
    monitor = Process.monitor(worker)
    send(worker, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
    attention = Battles.get(battle.id)
    assert attention.state == "needs_attention"
    assert attention.stage == "admission"
    assert attention.context["head"] == nil
    retained = Repo.get!(Attempt, attempt.id)
    assert retained.state == "interrupted"
    assert retained.result == receipt
    assert length(Battles.attempts(battle.id)) == 1
    :sys.resume(runner)
    refute_receive {:timed_handoff, _, _, _}, 100
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
  end

  test "a timing gap cancels the owned native helper and records cleanup without accepting work",
       ctx do
    helper = Path.join(ctx.source, "timing-helper")
    ready = Path.join(ctx.source, "timing-ready")
    done = Path.join(ctx.source, "timing-cleaned")

    File.write!(
      helper,
      "#!/bin/sh\nprintf ready > '" <>
        ready <>
        "'\nread line\nprintf cleaned > '" <>
        done <> "'\nprintf '%s\\n' '{\"status\":\"cancelled\",\"cleanup_verified\":true}'\n"
    )

    File.chmod!(helper, 0o700)
    previous = Application.get_env(:cuckoding, :native_helper)
    Application.put_env(:cuckoding, :native_helper, helper)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cuckoding, :native_helper, previous),
        else: Application.delete_env(:cuckoding, :native_helper)
    end)

    executor = fn attempt ->
      active? = fn ->
        :ok = Cuckoding.BattleClock.check()
        Battles.active_attempt?(attempt.id, attempt.claim_token)
      end

      receipt =
        Cuckoding.NativeHelper.request(%{id: attempt.id}, [], 10_000, &Jason.decode!/1, 8192,
          active?: active?
        )

      Map.merge(
        Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256)),
        Map.take(receipt, ~w(status cleanup_verified))
      )
    end

    {clock, runner} = clocked_runner(executor)
    battle = start(ctx.board)
    send(runner, :poll)
    await(fn -> File.exists?(ready) end)
    move_clock(clock, 10_000, 10_000)
    :ok = Cuckoding.BattleClock.check()
    await(fn -> Battles.get(battle.id).state == "needs_attention" end)
    assert File.read!(done) == "cleaned"
    [attempt] = Battles.attempts(battle.id)
    assert attempt.state == "interrupted"
    assert attempt.result["status"] == "cancelled"
    assert attempt.result["cleanup_verified"] == true
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
  end

  test "clock guard failure stops old workers before recovery can reset its baseline", ctx do
    parent = self()

    {_clock, runner} =
      clocked_runner(fn attempt ->
        send(parent, {:clock_owned_stage, self(), attempt})

        receive do
          :finish -> raise "must not resume this session"
        end
      end)

    battle = start(ctx.board)
    send(runner, :poll)
    assert_receive {:clock_owned_stage, worker, attempt}, 1_000
    monitor = Process.monitor(worker)
    guard = Process.whereis(Cuckoding.BattleClock)
    Process.exit(guard, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :shutdown}, 1_000

    await(fn ->
      is_pid(Process.whereis(Cuckoding.BattleClock)) and
        Process.whereis(Cuckoding.BattleClock) != guard
    end)

    await(fn -> Battles.get(battle.id).state == "needs_attention" end)
    assert Repo.get!(Attempt, attempt.id).state == "interrupted"
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    refute_receive {:clock_owned_stage, _, _}, 100
  end

  defp start_battle_tasks do
    unless Process.whereis(Cuckoding.BattleClock), do: start_supervised!(Cuckoding.BattleClock)
    start_supervised!({Task.Supervisor, name: Cuckoding.BattleTasks})
  end

  defp await(fun, remaining \\ 100)

  defp await(fun, remaining) when remaining > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      await(fun, remaining - 1)
    end
  end

  defp await(fun, 0), do: assert(fun.())
end
