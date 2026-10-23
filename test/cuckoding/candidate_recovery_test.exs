defmodule Cuckoding.CandidateRecoveryTest do
  use Cuckoding.DataCase
  import Cuckoding.BattleFixtures

  alias Cuckoding.{
    ArenaGit,
    BattleExecutor,
    BattleRunner,
    Battles,
    ExecutionSupervisor,
    Team,
    TeamAssignments,
    Workflows
  }

  alias Cuckoding.Battles.{Attempt, Battle, MixedClosure, ProviderClosure, Snapshot, Stages, Task}

  defmodule ReadGit do
    alias Cuckoding.ArenaGit

    def run(%{id: id, payload: payload}, options) do
      true = options[:active?].()
      request = payload["request"]

      if Process.get(:bad_cleanup),
        do: %{"cleanup_verified" => false},
        else: receipt(id, payload["operation"], request)
    end

    defp receipt(id, "recover_battle_candidate", request) do
      [] = request["files"]

      %{
        "status" => "candidate_captured",
        "key" => id,
        "worktree_key" => request["preparation"]["key"],
        "base" => request["preparation"]["head"],
        "candidate" => String.duplicate("c", 40),
        "tree" => String.duplicate("d", 40),
        "manifest_sha256" => String.duplicate("e", 64)
      }
    end

    defp receipt(id, "recover_battle_worktree", request) do
      %{
        "status" => "prepared",
        "key" => id,
        "head" => request["battle"]["head"],
        "path" => ArenaGit.worktree_path(id),
        "device" => 1,
        "inode" => 2
      }
    end
  end

  setup do
    ctx = fixture()
    root = "/private/tmp/cuckoding-candidate-recovery-#{Ecto.UUID.generate()}"
    source = Path.join(root, "source")
    File.mkdir_p!(source)
    home = Application.get_env(:cuckoding, :discovery_home)
    Application.put_env(:cuckoding, :discovery_home, Path.join(root, "home"))

    on_exit(fn ->
      Application.put_env(:cuckoding, :discovery_home, home)
      File.rm_rf!(root)
    end)

    {:ok, folder} = Cuckoding.Arenas.inspect_folder(source)
    arena = Cuckoding.Tabulae.arena(ctx.board.arena_id)

    Repo.update!(
      Ecto.Changeset.change(arena,
        path: folder["path"],
        device: folder["device"],
        inode: folder["inode"]
      )
    )

    ctx
  end

  defp finish(attempt) do
    receipt =
      case attempt.stage do
        "admission" ->
          result(attempt, %{
            "native_battle" => %{
              "status" => "battle_created",
              "key" => attempt.battle_id,
              "battle_key" => attempt.battle_id,
              "base" => String.duplicate("a", 40),
              "head" => String.duplicate("a", 40),
              "reference" => "refs/heads/ccoding/battles/" <> attempt.battle_id,
              "manifest_sha256" => String.duplicate("b", 64)
            }
          })

        "prepare_worktree" ->
          result(attempt, %{
            "preparation" => %{
              "key" => attempt.id,
              "head" => attempt.request["context"]["head"],
              "path" => ArenaGit.worktree_path(attempt.id),
              "device" => 1,
              "inode" => 2
            }
          })

        "implementor" ->
          put_in(result(attempt), ["provider", "changes"], [])

        _ ->
          result(attempt)
      end

    receipt =
      if Stages.access(attempt.request["snapshot"], attempt.stage) == "write",
        do:
          receipt
          |> put_in(["provider", "access"], "write")
          |> put_in(["provider", "changes"], []),
        else: receipt

    {:ok, next} = Battles.finish(attempt.id, attempt.claim_token, receipt)
    next
  end

  defp capture(battle) do
    {:ok, attempt} = Battles.claim_next(battle.id)
    if attempt.stage == "capture", do: attempt, else: capture(finish(attempt))
  end

  defp captured(attempt) do
    preparation = attempt.request["task_context"]["preparation"]

    candidate = %{
      "status" => "candidate_captured",
      "key" => attempt.id,
      "worktree_key" => preparation["key"],
      "base" => preparation["head"],
      "candidate" => String.duplicate("c", 40),
      "tree" => String.duplicate("d", 40),
      "manifest_sha256" => String.duplicate("e", 64)
    }

    result(attempt, %{"native_candidate" => candidate, "candidate_sha" => candidate["candidate"]})
  end

  defp interrupted(board, pair \\ nil) do
    if pair, do: save_task(board, "Independent", [])
    battle = start(board)
    first = capture(battle)

    second =
      case pair do
        "capture" ->
          capture(Battles.get(battle.id))

        "prepare_worktree" ->
          {:ok, preparing} = Battles.claim_next(battle.id)
          assert preparing.stage == "prepare_worktree"
          preparing

        nil ->
          nil
      end

    {:ok, _} = Battles.recover()

    {Battles.get(battle.id),
     Enum.map(Enum.reject([first, second], &is_nil/1), &Repo.get!(Attempt, &1.id))}
  end

  defp observation(%{stage: "capture"} = attempt), do: captured(attempt)

  defp observation(attempt) do
    result(attempt, %{
      "preparation" => %{
        "key" => attempt.id,
        "head" => attempt.request["context"]["head"],
        "path" => ArenaGit.worktree_path(attempt.id),
        "device" => 1,
        "inode" => 2
      }
    })
  end

  defp provider(battle) do
    {:ok, attempt} = Battles.claim_next(battle.id)
    if attempt.stage == "implementor", do: attempt, else: provider(finish(attempt))
  end

  defp mixed(board, kind, legacy? \\ false) do
    save_task(board, "Independent", [])
    battle = start(board)

    battle =
      if legacy? do
        {:ok, _} = Battles.stop(battle.id)
        snapshot = Map.delete(battle.snapshot, "mixed_closure")

        legacy =
          Repo.insert!(%Battle{
            id: Ecto.UUID.generate(),
            arena_id: battle.arena_id,
            tabula_id: battle.tabula_id,
            state: "running",
            stage: "admission",
            snapshot: snapshot,
            fingerprint: Snapshot.digest(snapshot),
            deadline_at: battle.deadline_at
          })

        for task <- Battles.tasks(battle.id),
            do:
              Repo.insert!(%Task{
                id: Ecto.UUID.generate(),
                battle_id: legacy.id,
                task_id: task.task_id,
                position: task.position,
                state: "pending",
                snapshot: task.snapshot
              })

        legacy
      else
        battle
      end

    native =
      if kind == "capture" do
        capture(battle)
      else
        {:ok, admission} = Battles.claim_next(battle.id)
        battle = finish(admission)
        {:ok, preparation} = Battles.claim_next(battle.id)
        assert preparation.stage == "prepare_worktree"
        preparation
      end

    provider = provider(Battles.get(battle.id))
    {:ok, _} = Battles.recover()
    {Battles.get(battle.id), Repo.get!(Attempt, provider.id), Repo.get!(Attempt, native.id)}
  end

  defp provider_observation(attempt, closed? \\ true) do
    BattleExecutor.reconcile_provider(attempt, fn exact, active? ->
      assert exact == attempt and active?.()

      ProviderClosure.binding_for(attempt)
      |> Map.take(~w(attempt_sha256 agent_id kind))
      |> Map.merge(%{
        "status" => "provider_closed",
        "request_id" => attempt.id,
        "cleanup_verified" => closed?,
        "pid" => 123,
        "spawned_at_ms" => 1000,
        "elapsed_ms" => 20,
        "receipt_sha256" => String.duplicate("a", 64)
      })
    end)
  end

  test "mixed provider/native closure allows Stop only after both exact proofs, never advancement",
       ctx do
    for kind <- ~w(capture prepare_worktree) do
      {battle, provider, native} = mixed(ctx.board, kind)
      tasks = Battles.tasks(battle.id)
      assert MixedClosure.enabled?(battle.snapshot)
      assert Battles.recovery_attempt() == provider
      refute Battles.candidate_reconciliation_current?(native)
      assert {:error, :cleanup_required} = Battles.stop(battle.id)

      assert {:error, :stale_reconciliation} =
               Battles.reconcile_recovery(native, observation(native))

      {:ok, pending} = Battles.reconcile_recovery(provider, provider_observation(provider))
      assert pending.state == "needs_attention" and Battles.recovery_attempt() == native
      assert {:error, :cleanup_required} = Battles.stop(battle.id)
      assert {:ok, _} = Battles.recover()
      assert Battles.recovery_attempt() == native

      receipt =
        if kind == "capture",
          do: BattleExecutor.reconcile_candidate(native, git: ReadGit),
          else: BattleExecutor.reconcile_preparation(native, git: ReadGit)

      assert receipt == observation(native)
      {:ok, retained} = Battles.reconcile_recovery(native, receipt)

      assert retained.state == "needs_attention" and
               retained.reason == "restart_requires_inspection"

      assert retained.context["head"] == battle.context["head"]

      assert retained.turns_used == battle.turns_used and
               retained.deadline_at == battle.deadline_at

      assert Battles.tasks(battle.id) == tasks and Battles.recovery_attempt() == nil

      assert Repo.get!(Attempt, provider.id) == provider and
               Repo.get!(Attempt, native.id) == native

      refute match?({:ok, _}, Battles.resume(battle.id, retained.control_revision))
      refute match?({:ok, _}, Battles.retry(battle.id, retained.control_revision))

      refute match?(
               {:ok, _},
               Battles.skip(battle.id, retained.control_revision, native.task_id, true)
             )

      assert {:error, :stale_reconciliation} = Battles.reconcile_recovery(native, receipt)
      assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
    end
  end

  test "mixed closure retains failures and rejects foreign native proofs without releasing Stop",
       ctx do
    {battle, provider, native} = mixed(ctx.board, "capture")
    {:ok, _} = Battles.reconcile_recovery(provider, provider_observation(provider, false))
    assert Battles.recovery_attempt() == native

    for path <- [
          ["request_id"],
          ["task_id"],
          ["native_candidate", "key"],
          ["native_candidate", "worktree_key"]
        ] do
      invalid = put_in(observation(native), path, Ecto.UUID.generate())
      assert {:error, reason} = Battles.reconcile_recovery(native, invalid)
      assert reason in [:foreign_result, :invalid_result]
      assert Battles.recovery_attempt() == native
    end

    {:ok, _} = Battles.reconcile_recovery(native, observation(native))
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    assert Repo.get!(Attempt, native.id) == native

    assert {:error, :stale_reconciliation} =
             Battles.reconcile_recovery(provider, provider_observation_after(provider))
  end

  defp provider_observation_after(attempt) do
    result(attempt, %{"status" => "closed", "cleanup_verified" => true})
    |> Map.drop(~w(provider candidate_sha))
  end

  test "missing native proof leaves mixed claims blocked even when provider closure verified",
       ctx do
    {battle, provider, native} = mixed(ctx.board, "prepare_worktree")
    {:ok, _} = Battles.reconcile_recovery(provider, provider_observation(provider))
    Process.put(:bad_cleanup, true)
    receipt = BattleExecutor.reconcile_preparation(native, git: ReadGit)
    Process.delete(:bad_cleanup)
    assert receipt["cleanup_verified"] == false
    {:ok, failed} = Battles.reconcile_recovery(native, receipt)
    assert failed.state == "needs_attention" and Battles.recovery_attempt() == nil
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
  end

  test "expired and timing-fenced mixed reads remain Stop-only", ctx do
    {battle, provider, native} = mixed(ctx.board, "capture")
    tasks = Battles.tasks(battle.id)
    {:ok, _} = Battles.reconcile_recovery(provider, provider_observation(provider))

    {:ok, observed} =
      Battles.reconcile_mixed_closure(native, observation(native), native.deadline_at)

    assert observed.state == "needs_attention" and Battles.tasks(battle.id) == tasks
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)

    {battle, provider, native} = mixed(ctx.board, "prepare_worktree")
    tasks = Battles.tasks(battle.id)
    {:ok, _} = Battles.reconcile_recovery(provider, provider_observation(provider))

    gap =
      Cuckoding.BattleClock.gap(
        {DateTime.utc_now(), 0},
        {DateTime.add(DateTime.utc_now(), -60), 1000}
      )

    {:ok, _} = Battles.observe_timing_gap(gap)
    refute Battles.candidate_reconciliation_current?(native)
    {:ok, observed} = Battles.reconcile_recovery(native, observation(native))
    assert observed.reason == "timing_gap" and observed.state == "needs_attention"
    assert Battles.tasks(battle.id) == tasks
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
  end

  test "old snapshots do not acquire mixed native closure authority", ctx do
    {battle, provider, native} = mixed(ctx.board, "capture", true)
    refute MixedClosure.enabled?(battle.snapshot)
    {:ok, _} = Battles.reconcile_recovery(provider, provider_observation(provider))
    assert Battles.recovery_attempt() == nil
    refute Battles.candidate_reconciliation_current?(native)

    assert {:error, :stale_reconciliation} =
             Battles.reconcile_recovery(native, observation(native))

    assert {:error, :cleanup_required} = Battles.stop(battle.id)
  end

  test "mixed pair admission refuses Stop, foreign scope and different policies",
       ctx do
    {battle, provider, native} = mixed(ctx.board, "capture")
    running = %{battle | state: "running"}
    assert MixedClosure.pair(running, [native, provider]) == battle.context["mixed_closure_pair"]

    for state <- ~w(stopping stopped needs_attention paused) do
      refute MixedClosure.pair(%{battle | state: state}, [provider, native])
    end

    for field <- ~w(mixed_closure parallelism candidate_recovery provider_closure) do
      refute MixedClosure.pair(%{running | snapshot: Map.delete(running.snapshot, field)}, [
               provider,
               native
             ])
    end

    refute MixedClosure.pair(running, [provider, %{native | task_id: provider.task_id}])
    refute MixedClosure.pair(running, [provider, %{native | battle_id: Ecto.UUID.generate()}])
    refute MixedClosure.pair(running, [provider, %{native | stage: "integrate"}])
    refute MixedClosure.pair(running, [provider])

    {:ok, _} = Battles.reconcile_recovery(provider, provider_observation(provider))
    {:ok, retained} = Battles.reconcile_recovery(native, observation(native))
    assert MixedClosure.closed?(retained, native)
    foreign = put_in(retained.context, ["mixed_closure_pair", "native_id"], Ecto.UUID.generate())
    refute MixedClosure.closed?(%{retained | context: foreign}, native)
  end

  test "a timing fence before restart cannot arm mixed native inspection", ctx do
    save_task(ctx.board, "Independent", [])
    battle = start(ctx.board)
    native = capture(battle)
    provider = provider(Battles.get(battle.id))

    gap =
      Cuckoding.BattleClock.gap(
        {DateTime.utc_now(), 0},
        {DateTime.add(DateTime.utc_now(), -60), 1000}
      )

    {:ok, _} = Battles.observe_timing_gap(gap)
    {:ok, _} = Battles.recover()
    retained = Battles.get(battle.id)
    refute retained.context["mixed_closure_pair"]
    refute Battles.candidate_reconciliation_current?(Repo.get!(Attempt, native.id))
    assert Battles.recovery_attempt().id == provider.id
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
  end

  test "mixed closure queue survives worker/coordinator loss without provider replay", ctx do
    {battle, provider, native} = mixed(ctx.board, "capture")
    owner = self()

    reconciler = fn attempt ->
      send(owner, {:mixed_read, self(), attempt})

      receive do
        :inspect ->
          if attempt.role,
            do: provider_observation(attempt),
            else: BattleExecutor.reconcile_candidate(attempt, git: ReadGit)
      end
    end

    start_supervised!(
      {ExecutionSupervisor,
       coordinator: BattleRunner,
       tasks: Cuckoding.BattleTasks,
       options: [
         reconciler: reconciler,
         executor: fn attempt -> send(owner, {:unexpected_execution, attempt}) end
       ]}
    )

    assert_receive {:mixed_read, provider_worker, ^provider}, 1000
    send(provider_worker, :inspect)
    assert_receive {:mixed_read, native_worker, ^native}, 1000
    monitor = Process.monitor(native_worker)
    Process.exit(Process.whereis(BattleRunner), :kill)
    assert_receive {:DOWN, ^monitor, :process, ^native_worker, :shutdown}, 1000
    assert_receive {:mixed_read, replacement, ^native}, 1000
    send(replacement, :inspect)
    deadline = System.monotonic_time(:millisecond) + 2000
    await_closure(battle.id, native.id, deadline)
    assert Repo.get!(Attempt, provider.id) == provider and Repo.get!(Attempt, native.id) == native
    assert Battles.get(battle.id).state == "needs_attention"

    assert Enum.count(Battles.evidence(battle.id), &(&1.kind == "battle.mixed_closure_observed")) ==
             1

    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
    refute_receive {:mixed_read, _, _}
    refute_receive {:unexpected_execution, _}
  end

  defp await_closure(id, attempt_id, deadline) do
    if Battles.get(id).context["mixed_closures"][attempt_id],
      do: :ok,
      else:
        (
          assert System.monotonic_time(:millisecond) < deadline
          Process.sleep(10)
          await_closure(id, attempt_id, deadline)
        )
  end

  test "complete retained capture becomes a paused next checkpoint without rewriting its attempt",
       ctx do
    {battle, [attempt]} = interrupted(ctx.board)
    assert battle.snapshot["candidate_recovery"] == "retained-candidate-wave-v1"
    assert Battles.recovery_attempt() == attempt
    {:ok, paused} = Battles.reconcile_recovery(attempt, captured(attempt))
    assert paused.state == "paused" and paused.stage == "checks"
    assert paused.turns_used == battle.turns_used and paused.deadline_at == battle.deadline_at
    assert Repo.get!(Attempt, attempt.id) == attempt
    assert hd(Battles.tasks(battle.id)).context["candidate_sha"] == String.duplicate("c", 40)

    assert {:error, :stale_reconciliation} =
             Battles.reconcile_recovery(attempt, captured(attempt))

    assert {:ok, resumed} = Battles.resume(paused.id, paused.control_revision)
    assert {:ok, next} = Battles.claim_next(resumed.id)
    assert next.stage == "checks"
  end

  test "capture pairs and mixed preparation/capture pairs advance atomically after every read",
       ctx do
    for kind <- ["capture", "prepare_worktree"] do
      {battle, [first, second]} = interrupted(ctx.board, kind)
      assert Battles.recovery_attempt() == first
      {:ok, pending} = Battles.reconcile_recovery(first, captured(first))
      assert pending.state == "needs_attention"
      refute hd(Battles.tasks(battle.id)).context["native_candidate"]
      assert Battles.recovery_attempt() == second
      assert {:error, :cleanup_required} = Battles.stop(battle.id)
      {:ok, paused} = Battles.reconcile_recovery(second, observation(second))
      assert paused.state == "paused"
      assert paused.turns_used == battle.turns_used
      assert Repo.get!(Attempt, first.id) == first and Repo.get!(Attempt, second.id) == second

      for member <- [first, second] do
        task = Enum.find(Battles.tasks(battle.id), &(&1.task_id == member.task_id))

        assert task.context["lane_stage"] ==
                 if(member.stage == "capture", do: "checks", else: "coordinator")
      end

      assert {:ok, _} = Battles.stop(battle.id)
    end
  end

  test "missing proof or a late member never partially advances the wave", ctx do
    {battle, [first, second]} = interrupted(ctx.board, "capture")

    failure =
      result(first, %{
        "status" => "failed",
        "reason" => "reconciliation_failed",
        "cleanup_verified" => false
      })
      |> Map.drop(~w(native_candidate candidate_sha))

    {:ok, _} = Battles.reconcile_recovery(first, failure)
    {:ok, retained} = Battles.reconcile_recovery(second, captured(second))
    assert retained.state == "needs_attention"
    assert Enum.all?(Battles.tasks(battle.id), &is_nil(&1.context["native_candidate"]))
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    assert Repo.get!(Attempt, first.id) == first
  end

  test "executor performs fixed reads for both members and preserves false cleanup", ctx do
    {battle, [first, second]} = interrupted(ctx.board, "prepare_worktree")
    Process.put(:bad_cleanup, true)
    failed = BattleExecutor.reconcile_candidate(first, git: ReadGit)
    assert failed["cleanup_verified"] == false and failed["status"] == "failed"
    Process.delete(:bad_cleanup)
    receipt = BattleExecutor.reconcile_candidate(first, git: ReadGit)
    assert receipt == captured(first)
    {:ok, _} = Battles.reconcile_recovery(first, receipt)
    receipt = BattleExecutor.reconcile_preparation(second, git: ReadGit)
    assert receipt == observation(second)
    {:ok, paused} = Battles.reconcile_recovery(second, receipt)
    assert paused.state == "paused" and paused.turns_used == battle.turns_used
  end

  test "expired or timing-fenced reads close Stop without advancing either lane", ctx do
    {battle, [first, second]} = interrupted(ctx.board, "capture")
    {:ok, _} = Battles.reconcile_candidate(first, captured(first))
    {:ok, expired} = Battles.reconcile_candidate(second, captured(second), second.deadline_at)
    assert expired.state == "needs_attention" and expired.reason == "late_result_rejected"
    assert Enum.all?(Battles.tasks(battle.id), &is_nil(&1.context["native_candidate"]))
    assert {:error, _} = Battles.resume(battle.id, expired.control_revision)
    assert {:ok, _} = Battles.stop(battle.id)

    {battle, [attempt]} = interrupted(ctx.board)

    gap =
      Cuckoding.BattleClock.gap(
        {DateTime.utc_now(), 0},
        {DateTime.add(DateTime.utc_now(), -60), 1000}
      )

    {:ok, _} = Battles.observe_timing_gap(gap)
    refute Battles.candidate_reconciliation_current?(attempt)
    {:ok, fenced} = Battles.reconcile_candidate(attempt, captured(attempt))
    assert fenced.reason == "timing_gap" and fenced.state == "needs_attention"
    refute hd(Battles.tasks(battle.id)).context["native_candidate"]
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
  end

  test "foreign observations and old policies cannot acquire recovery authority", ctx do
    {battle, [attempt]} = interrupted(ctx.board)

    for path <- [
          ["request_id"],
          ["task_id"],
          ["native_candidate", "key"],
          ["native_candidate", "worktree_key"]
        ] do
      bad = put_in(captured(attempt), path, Ecto.UUID.generate())
      assert {:error, reason} = Battles.reconcile_recovery(attempt, bad)
      assert reason in [:foreign_result, :invalid_result]
    end

    assert Battles.recovery_attempt() == attempt
    {:ok, _} = Battles.reconcile_candidate(attempt, captured(attempt))
    {:ok, _} = Battles.stop(battle.id)
    modern = start(ctx.board)
    {:ok, _} = Battles.stop(modern.id)
    snapshot = Map.delete(modern.snapshot, "candidate_recovery")

    legacy =
      Repo.insert!(%Battle{
        id: Ecto.UUID.generate(),
        arena_id: modern.arena_id,
        tabula_id: modern.tabula_id,
        state: "running",
        stage: "admission",
        snapshot: snapshot,
        fingerprint: Snapshot.digest(snapshot),
        deadline_at: modern.deadline_at
      })

    for task <- Battles.tasks(modern.id),
        do:
          Repo.insert!(%Task{
            id: Ecto.UUID.generate(),
            battle_id: legacy.id,
            task_id: task.task_id,
            position: task.position,
            state: "pending",
            snapshot: task.snapshot
          })

    capture = capture(legacy)
    {:ok, _} = Battles.recover()
    refute Battles.recovery_attempt()
    assert {:error, :cleanup_required} = Battles.stop(legacy.id)

    assert {:error, :stale_reconciliation} =
             Battles.reconcile_candidate(Repo.get!(Attempt, capture.id), captured(capture))
  end

  test "custom pre-Implementor capture resumes its exact frozen continuation", ctx do
    old = TeamAssignments.assigned(ctx.board)

    role =
      Team.custom_role()
      |> Map.merge(%{"name" => "Prepare", "agent" => "codex", "model_id" => "test-id"})

    {:ok, team} =
      Team.save(Ecto.UUID.generate(), old.id, Team.editable(old) ++ [role], false, ctx.board)

    step = %{
      "key" => "step_" <> Ecto.UUID.generate(),
      "name" => "Prepare",
      "role" => role["id"],
      "access" => "write",
      "position" => "before"
    }

    {:ok, _} =
      Workflows.configure_execution(
        Ecto.UUID.generate(),
        ctx.board.arena_id,
        ctx.board.id,
        0,
        team.id,
        Workflows.labels(ctx.board.definition),
        [step]
      )

    {battle, [attempt]} = interrupted(ctx.board)
    assert attempt.request["task_context"]["writer_stage"] == step["key"]
    receipt = BattleExecutor.reconcile_candidate(attempt, git: ReadGit)
    {:ok, paused} = Battles.reconcile_recovery(attempt, receipt)
    assert paused.stage == "implementor" and paused.state == "paused"
    {:ok, resumed} = Battles.resume(battle.id, paused.control_revision)
    {:ok, next} = Battles.claim_next(resumed.id)
    assert next.stage == "implementor"
    assert next.request["task_context"]["native_candidate"] == receipt["native_candidate"]
    assert Repo.get!(Attempt, attempt.id) == attempt
  end

  test "one supervised worker reads a mixed queue and commits before returning", ctx do
    {battle, [first, second]} = interrupted(ctx.board, "prepare_worktree")
    owner = self()

    reconciler = fn attempt ->
      send(owner, {:checkpoint_read, self(), attempt.id})

      if attempt.stage == "capture",
        do: BattleExecutor.reconcile_candidate(attempt, git: ReadGit),
        else: BattleExecutor.reconcile_preparation(attempt, git: ReadGit)
    end

    start_supervised!(
      {ExecutionSupervisor,
       coordinator: BattleRunner, tasks: Cuckoding.BattleTasks, options: [reconciler: reconciler]}
    )

    assert_receive {:checkpoint_read, worker, id}, 2000
    assert id == first.id and worker != owner
    assert_receive {:checkpoint_read, other, id}, 2000
    assert id == second.id and other != worker
    deadline = System.monotonic_time(:millisecond) + 2000
    await_paused(battle.id, deadline)
    assert Battles.recovery_attempt() == nil
    assert Repo.get!(Attempt, first.id) == first and Repo.get!(Attempt, second.id) == second
  end

  test "a preparation admitted before its sibling capture remains first in the mixed queue",
       ctx do
    save_task(ctx.board, "Independent", [])
    battle = start(ctx.board)
    {:ok, admission} = Battles.claim_next(battle.id)
    battle = finish(admission)
    {:ok, first} = Battles.claim_next(battle.id)
    {:ok, older_preparation} = Battles.claim_next(battle.id)
    assert first.stage == "prepare_worktree" and older_preparation.stage == "prepare_worktree"
    newer_capture = capture(finish(first))
    {:ok, _} = Battles.recover()
    first = Repo.get!(Attempt, older_preparation.id)
    second = Repo.get!(Attempt, newer_capture.id)
    assert Battles.recovery_attempt() == first
    first_receipt = BattleExecutor.reconcile_preparation(first, git: ReadGit)
    {:ok, pending} = Battles.reconcile_recovery(first, first_receipt)
    assert pending.state == "needs_attention" and Battles.recovery_attempt() == second
    second_receipt = BattleExecutor.reconcile_candidate(second, git: ReadGit)
    {:ok, paused} = Battles.reconcile_recovery(second, second_receipt)
    assert paused.state == "paused" and paused.turns_used == Battles.get(battle.id).turns_used
    assert Repo.get!(Attempt, first.id) == first and Repo.get!(Attempt, second.id) == second
  end

  test "coordinator restart repeats only the unfinished checkpoint read", ctx do
    {battle, [first, second]} = interrupted(ctx.board, "capture")
    owner = self()

    reconciler = fn attempt ->
      send(owner, {:checkpoint_wait, self(), attempt})

      receive do
        :inspect -> observation(attempt)
      end
    end

    start_supervised!(
      {ExecutionSupervisor,
       coordinator: BattleRunner, tasks: Cuckoding.BattleTasks, options: [reconciler: reconciler]}
    )

    assert_receive {:checkpoint_wait, first_worker, ^first}, 1000
    send(first_worker, :inspect)
    assert_receive {:checkpoint_wait, second_worker, ^second}, 1000
    assert Enum.all?(Battles.tasks(battle.id), &is_nil(&1.context["native_candidate"]))
    monitor = Process.monitor(second_worker)
    Process.exit(Process.whereis(BattleRunner), :kill)
    assert_receive {:DOWN, ^monitor, :process, ^second_worker, :shutdown}, 1000
    assert_receive {:checkpoint_wait, replacement, ^second}, 1000
    send(replacement, :inspect)
    await_paused(battle.id, System.monotonic_time(:millisecond) + 2000)

    assert Enum.count(Battles.evidence(battle.id), &(&1.kind == "battle.candidate_reconciled")) ==
             2

    assert Repo.get!(Attempt, first.id) == first and Repo.get!(Attempt, second.id) == second
    refute_receive {:checkpoint_wait, _, _}
  end

  defp await_paused(id, deadline) do
    if Battles.get(id).state == "paused",
      do: :ok,
      else:
        (
          assert System.monotonic_time(:millisecond) < deadline
          Process.sleep(10)
          await_paused(id, deadline)
        )
  end
end
