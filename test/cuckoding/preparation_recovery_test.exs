defmodule Cuckoding.PreparationRecoveryTest do
  use Cuckoding.DataCase
  import Cuckoding.BattleFixtures
  alias Cuckoding.{ArenaGit, BattleExecutor, BattleRunner, Battles, ExecutionSupervisor, Repo}
  alias Cuckoding.Battles.{Attempt, Battle, Snapshot}

  setup do
    ctx = fixture()
    root = "/private/tmp/cuckoding-preparation-test-#{Ecto.UUID.generate()}"
    source = Path.join(root, "source")
    previous_home = Application.get_env(:cuckoding, :discovery_home)
    File.mkdir_p!(source)
    Application.put_env(:cuckoding, :discovery_home, Path.join(root, "home"))

    on_exit(fn ->
      Application.put_env(:cuckoding, :discovery_home, previous_home)
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

  defp preparing(board, battle \\ nil) do
    battle = battle || start(board)
    {:ok, admission} = Battles.claim_next(battle.id)

    {:ok, _} =
      Battles.finish(
        admission.id,
        admission.claim_token,
        result(admission, %{
          "native_battle" => %{
            "status" => "battle_created",
            "key" => battle.id,
            "battle_key" => battle.id,
            "base" => String.duplicate("a", 40),
            "head" => String.duplicate("a", 40),
            "reference" => "refs/heads/ccoding/battles/" <> battle.id,
            "manifest_sha256" => String.duplicate("b", 64)
          }
        })
      )

    {:ok, preparing} = Battles.claim_next(battle.id)
    assert preparing.stage == "prepare_worktree"
    {Battles.get(battle.id), preparing}
  end

  defp interrupted(board) do
    {battle, preparing} = preparing(board)
    assert {:ok, _} = Battles.recover()
    {Battles.get(battle.id), Repo.get!(Attempt, preparing.id)}
  end

  defp prepared(attempt) do
    result(attempt, %{
      "preparation" => %{
        "key" => attempt.id,
        "head" => attempt.request["context"]["head"],
        "path" => ArenaGit.worktree_path(attempt.id),
        "device" => 17,
        "inode" => 19
      }
    })
  end

  test "complete retained preparation appends a paused checkpoint without replay", ctx do
    {battle, attempt} = interrupted(ctx.board)
    assert battle.snapshot["worktree_recovery"] == "retained-preparation-v1"
    assert Battles.recovery_attempt() == attempt
    assert Battles.preparation_reconciliation_current?(attempt)
    original_turns = battle.turns_used
    assert {:ok, paused} = Battles.reconcile_preparation(attempt, prepared(attempt))
    assert paused.state == "paused" and paused.stage == "coordinator"
    assert paused.turns_used == original_turns and paused.deadline_at == battle.deadline_at
    assert Repo.get!(Attempt, attempt.id) == attempt
    assert length(Battles.attempts(battle.id)) == 2
    assert Battles.recovery_attempt() == nil

    assert paused.context["preparation_reconciliations"][attempt.id]["receipt"] ==
             prepared(attempt)

    assert {:error, :stale_reconciliation} =
             Battles.reconcile_preparation(attempt, prepared(attempt))

    assert {:ok, resumed} = Battles.resume(paused.id, paused.control_revision)
    assert {:ok, next} = Battles.claim_next(resumed.id)
    assert next.stage == "coordinator"
    assert next.request["task_context"]["preparation"] == prepared(attempt)["preparation"]
  end

  test "foreign, malformed and stale observations cannot establish cleanup", ctx do
    {battle, attempt} = interrupted(ctx.board)

    for fields <- [
          %{"task_id" => Ecto.UUID.generate()},
          %{"request_id" => Ecto.UUID.generate()},
          %{
            "preparation" =>
              Map.put(prepared(attempt)["preparation"], "key", Ecto.UUID.generate())
          },
          %{
            "preparation" => Map.put(prepared(attempt)["preparation"], "path", "/private/foreign")
          },
          %{
            "preparation" =>
              Map.put(prepared(attempt)["preparation"], "head", String.duplicate("f", 40))
          },
          %{"preparation" => Map.put(prepared(attempt)["preparation"], "raw", "CANARY")},
          %{"cleanup_verified" => false}
        ] do
      assert {:error, _} =
               Battles.reconcile_preparation(attempt, Map.merge(prepared(attempt), fields))
    end

    assert Battles.get(battle.id) == battle
    assert {:error, :cleanup_required} = Battles.stop(battle.id)

    failure =
      result(attempt, %{
        "status" => "failed",
        "reason" => "reconciliation_failed",
        "cleanup_verified" => false
      })
      |> Map.delete("preparation")

    assert {:error, :invalid_result} =
             Battles.reconcile_preparation(
               attempt,
               Map.put(failure, "provider", %{"raw" => "CANARY"})
             )

    assert {:ok, failed} = Battles.reconcile_preparation(attempt, failure)
    assert failed.state == "needs_attention"
    assert Battles.recovery_attempt() == nil
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
  end

  test "older policies cannot recover multiple interrupted native preparations", ctx do
    save_task(ctx.board, "Another independent task", [])
    legacy = historical(ctx.board, ["worktree_wave_recovery"])
    {battle, first} = preparing(ctx.board, legacy)
    assert {:ok, second} = Battles.claim_next(battle.id)
    assert second.stage == "prepare_worktree" and second.task_id != first.task_id
    assert {:ok, _} = Battles.recover()
    assert Battles.recovery_attempt() == nil

    for attempt <- [first, second] do
      interrupted = Repo.get!(Attempt, attempt.id)
      assert interrupted.state == "interrupted"
      refute Battles.preparation_reconciliation_current?(interrupted)

      assert {:error, :stale_reconciliation} =
               Battles.reconcile_preparation(interrupted, prepared(interrupted))
    end

    assert {:error, :cleanup_required} = Battles.stop(battle.id)
  end

  test "Stop before restart cannot authorize preparation recovery", ctx do
    {battle, _} = preparing(ctx.board)
    assert {:ok, %{state: "stopping"}} = Battles.stop(battle.id)
    assert {:ok, _} = Battles.recover()
    assert Battles.recovery_attempt() == nil
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
  end

  test "a timing fence before restart cannot authorize preparation recovery", ctx do
    {battle, _} = preparing(ctx.board)
    now = DateTime.utc_now()
    gap = Cuckoding.BattleClock.gap({now, 0}, {DateTime.add(now, 60), 60_000})
    assert {:ok, _} = Battles.observe_timing_gap(gap)
    assert {:ok, _} = Battles.recover()
    assert Battles.recovery_attempt() == nil
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
  end

  test "expired preparation evidence permits Stop but never continuation", ctx do
    {battle, attempt} = interrupted(ctx.board)

    assert {:ok, retained} =
             Battles.reconcile_preparation(attempt, prepared(attempt), attempt.deadline_at)

    assert retained.state == "needs_attention" and retained.reason == "late_result_rejected"
    assert retained.stage == "prepare_worktree"
    refute Battles.retry_available?(retained)
    assert Battles.skip_preview(retained) == []
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
    assert Repo.get!(Attempt, attempt.id) == attempt
  end

  test "Resume revalidates exact connection and keeps the original deadline", ctx do
    {battle, attempt} = interrupted(ctx.board)
    {:ok, paused} = Battles.reconcile_preparation(attempt, prepared(attempt))
    workspace = Cuckoding.Foundation.workspace()

    Repo.update!(
      Ecto.Changeset.change(workspace,
        connection: Map.put(workspace.connection, "authorization", "not_connected")
      )
    )

    assert {:error, :resume_binding_changed} = Battles.resume(battle.id, paused.control_revision)
    assert Battles.get(battle.id) == paused

    Repo.update!(
      Ecto.Changeset.change(Cuckoding.Foundation.workspace(), connection: workspace.connection)
    )

    assert {:error, "deadline_exceeded"} =
             Battles.resume(battle.id, paused.control_revision, battle.deadline_at)

    assert Battles.get(battle.id).deadline_at == battle.deadline_at
    assert Repo.get!(Attempt, attempt.id) == attempt
  end

  test "a timing fence racing a completed read retains closure without accepting preparation",
       ctx do
    {battle, attempt} = interrupted(ctx.board)

    observation =
      Cuckoding.BattleClock.gap(
        {DateTime.utc_now(), 0},
        {DateTime.add(DateTime.utc_now(), -60), 1000}
      )

    assert {:ok, _} = Battles.observe_timing_gap(observation)
    refute Battles.preparation_reconciliation_current?(attempt)
    assert {:ok, retained} = Battles.reconcile_preparation(attempt, prepared(attempt))
    assert retained.state == "needs_attention" and retained.reason == "timing_gap"
    assert retained.stage == "prepare_worktree"
    assert {:error, _} = Battles.resume(retained.id, retained.control_revision)
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
  end

  defp historical(board, omitted) do
    battle = start(board)
    {:ok, _} = Battles.stop(battle.id)
    snapshot = Map.drop(battle.snapshot, omitted)

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
          Repo.insert!(%Cuckoding.Battles.Task{
            id: Ecto.UUID.generate(),
            battle_id: legacy.id,
            task_id: task.task_id,
            position: task.position,
            state: "pending",
            snapshot: task.snapshot
          })

    legacy
  end

  test "old policies gain no authority", ctx do
    legacy = historical(ctx.board, ["worktree_recovery", "worktree_wave_recovery"])
    {:ok, admission} = Battles.claim_next(legacy.id)
    {:ok, _} = Battles.finish(admission.id, admission.claim_token, result(admission))
    {:ok, _} = Battles.claim_next(legacy.id)
    {:ok, _} = Battles.recover()
    assert Battles.recovery_attempt() == nil
    assert {:error, :cleanup_required} = Battles.stop(legacy.id)
  end

  defp interrupted_pair(board) do
    save_task(board, "Another independent task", [])
    {battle, first} = preparing(board)
    {:ok, second} = Battles.claim_next(battle.id)
    assert second.stage == "prepare_worktree" and first.task_id != second.task_id
    {:ok, _} = Battles.recover()
    {Battles.get(battle.id), Enum.map([first, second], &Repo.get!(Attempt, &1.id))}
  end

  test "two retained preparations advance together only after both exact reads verify", ctx do
    {battle, [first, second]} = interrupted_pair(ctx.board)
    assert battle.snapshot["worktree_wave_recovery"] == "retained-preparation-wave-v1"
    assert Battles.recovery_attempt() == first
    {:ok, pending} = Battles.reconcile_preparation(first, prepared(first))
    assert pending.state == "needs_attention"
    assert Battles.recovery_attempt() == second
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    assert {:error, :stale_reconciliation} = Battles.reconcile_preparation(first, prepared(first))
    assert Enum.all?(Battles.tasks(battle.id), &is_nil(&1.context["preparation"]))
    {:ok, paused} = Battles.reconcile_preparation(second, prepared(second))
    assert paused.state == "paused" and paused.stage == "coordinator"
    assert paused.turns_used == battle.turns_used and paused.deadline_at == battle.deadline_at

    for attempt <- [first, second] do
      assert Repo.get!(Attempt, attempt.id) == attempt
      task = Enum.find(Battles.tasks(battle.id), &(&1.task_id == attempt.task_id))
      assert task.context["lane_stage"] == "coordinator"
      assert task.context["worker_slot"] == attempt.request["task_context"]["worker_slot"]
      assert task.context["preparation"] == prepared(attempt)["preparation"]
    end

    assert length(Battles.attempts(battle.id)) == 3
    assert Battles.recovery_attempt() == nil
    assert Enum.count(Battles.evidence(battle.id), &(&1.kind == "battle.recovery_paused")) == 1
    assert {:ok, resumed} = Battles.resume(battle.id, paused.control_revision)
    assert {:ok, next} = Battles.claim_next(resumed.id)
    assert next.stage == "coordinator"
  end

  test "one failed read retains both preparations without a partial checkpoint", ctx do
    {battle, [first, second]} = interrupted_pair(ctx.board)

    assert {:error, :stale_reconciliation} =
             Battles.reconcile_preparation(second, prepared(second))

    failure =
      result(first, %{
        "status" => "failed",
        "reason" => "reconciliation_failed",
        "cleanup_verified" => false
      })
      |> Map.delete("preparation")

    {:ok, _} = Battles.reconcile_preparation(first, failure)
    assert Battles.recovery_attempt() == second
    {:ok, retained} = Battles.reconcile_preparation(second, prepared(second))
    assert retained.state == "needs_attention"
    assert Enum.all?(Battles.tasks(battle.id), &is_nil(&1.context["preparation"]))
    assert Battles.recovery_attempt() == nil
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    assert {:error, _} = Battles.resume(battle.id, retained.control_revision)
    assert Repo.get!(Attempt, first.id) == first
    assert Repo.get!(Attempt, second.id) == second
  end

  test "a mixed provider and native interruption cannot become a preparation wave", ctx do
    save_task(ctx.board, "Another independent task", [])
    {battle, first} = preparing(ctx.board)
    {:ok, second} = Battles.claim_next(battle.id)
    {:ok, _} = Battles.finish(first.id, first.claim_token, prepared(first))
    {:ok, provider} = Battles.claim_next(battle.id)
    assert provider.stage == "coordinator"
    {:ok, _} = Battles.recover()
    retained = Battles.get(battle.id)
    assert retained.context["preparation_recovery_wave"] == nil
    assert retained.context["preparation_recovery_pending"] == nil
    assert Battles.recovery_attempt().id == provider.id
    interrupted = Repo.get!(Attempt, second.id)

    assert BattleExecutor.reconcile_preparation(interrupted, git: __MODULE__.Git)[
             "cleanup_verified"
           ] == false

    refute_receive {:recovery_operation, _, _}
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
  end

  test "expiry of either original preparation blocks advancement of both tasks", ctx do
    {battle, [first, second]} = interrupted_pair(ctx.board)
    {:ok, _} = Battles.reconcile_preparation(first, prepared(first), first.deadline_at)

    {:ok, retained} =
      Battles.reconcile_preparation(second, prepared(second), first.deadline_at)

    assert retained.state == "needs_attention" and retained.reason == "late_result_rejected"
    assert Enum.all?(Battles.tasks(battle.id), &is_nil(&1.context["preparation"]))
    refute Battles.retry_available?(retained)
    assert Battles.skip_preview(retained) == []
    assert {:error, _} = Battles.resume(battle.id, retained.control_revision)
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
    assert length(Battles.attempts(battle.id)) == 3
  end

  test "a fence racing the last read retains only whole-wave Stop closure", ctx do
    {battle, [first, second]} = interrupted_pair(ctx.board)
    {:ok, _} = Battles.reconcile_preparation(first, prepared(first))
    receipt = BattleExecutor.reconcile_preparation(second, git: __MODULE__.Git)
    assert receipt == prepared(second)
    now = DateTime.utc_now()
    gap = Cuckoding.BattleClock.gap({now, 0}, {DateTime.add(now, 60), 60_000})
    {:ok, _} = Battles.observe_timing_gap(gap)
    refute Battles.preparation_reconciliation_current?(second)
    {:ok, retained} = Battles.reconcile_preparation(second, receipt)
    assert retained.state == "needs_attention" and retained.reason == "timing_gap"
    assert Enum.all?(Battles.tasks(battle.id), &is_nil(&1.context["preparation"]))
    assert Battles.recovery_attempt() == nil
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
  end

  test "a fence between reads prevents the next read and leaves unknown cleanup blocked", ctx do
    {battle, [first, second]} = interrupted_pair(ctx.board)
    {:ok, _} = Battles.reconcile_preparation(first, prepared(first))
    now = DateTime.utc_now()

    {:ok, _} =
      Battles.observe_timing_gap(
        Cuckoding.BattleClock.gap({now, 0}, {DateTime.add(now, -60), 1000})
      )

    assert Battles.recovery_attempt() == nil
    assert BattleExecutor.reconcile_preparation(second, git: __MODULE__.Git)["status"] == "failed"
    refute_receive {:recovery_operation, _, _}
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    assert Enum.all?(Battles.tasks(battle.id), &is_nil(&1.context["preparation"]))
  end

  test "coordinator restart repeats only the unfinished read of a retained preparation wave",
       ctx do
    {battle, [first, second]} = interrupted_pair(ctx.board)
    parent = self()

    reconciler = fn interrupted ->
      send(parent, {:wave_read, self(), interrupted})

      receive do
        :inspect -> prepared(interrupted)
      end
    end

    start_supervised!(
      {ExecutionSupervisor,
       coordinator: BattleRunner, tasks: Cuckoding.BattleTasks, options: [reconciler: reconciler]}
    )

    assert_receive {:wave_read, first_worker, ^first}, 1_000
    send(first_worker, :inspect)
    assert_receive {:wave_read, second_worker, ^second}, 1_000
    assert Enum.all?(Battles.tasks(battle.id), &is_nil(&1.context["preparation"]))
    monitor = Process.monitor(second_worker)
    Process.exit(Process.whereis(BattleRunner), :kill)
    assert_receive {:DOWN, ^monitor, :process, ^second_worker, :shutdown}, 1_000
    assert_receive {:wave_read, replacement, ^second}, 1_000
    send(replacement, :inspect)
    await(fn -> Battles.get(battle.id).state == "paused" end)
    assert Repo.get!(Attempt, first.id) == first
    assert Repo.get!(Attempt, second.id) == second
    assert length(Battles.attempts(battle.id)) == 3

    assert Enum.count(Battles.evidence(battle.id), &(&1.kind == "battle.preparation_reconciled")) ==
             2

    assert Enum.count(Battles.evidence(battle.id), &(&1.kind == "battle.recovery_paused")) == 1
    refute_receive {:wave_read, _, _}
  end

  defmodule Git do
    def run(%{id: id, payload: payload}, _) do
      send(self(), {:recovery_operation, payload["operation"], payload["request"]})

      Map.merge(
        %{
          "status" => "prepared",
          "key" => id,
          "head" => payload["request"]["battle"]["head"],
          "path" => ArenaGit.worktree_path(id),
          "device" => 17,
          "inode" => 19
        },
        Process.get(:preparation_override, %{})
      )
    end
  end

  test "executor uses only the fixed retained read and exact original request", ctx do
    {_battle, attempt} = interrupted(ctx.board)
    receipt = BattleExecutor.reconcile_preparation(attempt, git: Git)
    assert receipt == prepared(attempt)
    assert_receive {:recovery_operation, "recover_battle_worktree", request}

    assert request == %{
             "key" => attempt.id,
             "battle" => attempt.request["context"]["native_battle"]
           }
  end

  test "executor refuses uncertain cleanup and stale reads without promoting success", ctx do
    {battle, attempt} = interrupted(ctx.board)

    for cleanup <- [false, nil, "true"] do
      Process.put(:preparation_override, %{"cleanup_verified" => cleanup})
      receipt = BattleExecutor.reconcile_preparation(attempt, git: Git)
      assert receipt["status"] == "failed" and receipt["cleanup_verified"] == false
      assert_receive {:recovery_operation, "recover_battle_worktree", _}
    end

    Process.delete(:preparation_override)
    assert {:ok, _} = Battles.reconcile_preparation(attempt, prepared(attempt))
    assert BattleExecutor.reconcile_preparation(attempt, git: Git)["status"] == "failed"
    refute_receive {:recovery_operation, _, _}
    assert Battles.get(battle.id).state == "paused"
  end

  test "supervised recovery is exclusive and survives coordinator loss without replay", ctx do
    {battle, attempt} = interrupted(ctx.board)
    parent = self()

    reconciler = fn interrupted ->
      send(parent, {:reading_preparation, self(), interrupted})

      receive do
        :inspect -> prepared(interrupted)
      end
    end

    executor = fn stage ->
      send(parent, {:unexpected_stage, stage.id})
      result(stage)
    end

    start_supervised!(
      {ExecutionSupervisor,
       coordinator: BattleRunner,
       tasks: Cuckoding.BattleTasks,
       options: [reconciler: reconciler, executor: executor]}
    )

    assert_receive {:reading_preparation, worker, ^attempt}, 1_000
    runner = Process.whereis(BattleRunner)
    assert worker != runner and worker in Task.Supervisor.children(Cuckoding.BattleTasks)
    other_arena = Cuckoding.DataCase.arena_fixture()
    {:ok, board} = Cuckoding.Tabulae.create(Ecto.UUID.generate(), other_arena.id, "Other")
    save_task(board, "Independent Arena", [])
    other = start(board)
    send(runner, :poll)
    assert map_size(:sys.get_state(runner).jobs) == 1
    assert Battles.attempts(other.id) == []
    {:ok, _} = Battles.pause(other.id, other.control_revision)

    monitor = Process.monitor(worker)
    Process.exit(runner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :shutdown}, 1_000
    assert_receive {:reading_preparation, replacement, ^attempt}, 1_000
    assert replacement != worker
    send(replacement, :inspect)
    await(fn -> Battles.get(battle.id).state == "paused" end)
    assert Repo.get!(Attempt, attempt.id) == attempt
    assert length(Battles.attempts(battle.id)) == 2

    assert Enum.count(Battles.evidence(battle.id), &(&1.kind == "battle.preparation_reconciled")) ==
             1

    refute_receive {:reading_preparation, _, _}
    refute_receive {:unexpected_stage, _}
  end

  defp await(check, remaining \\ 200) do
    if not check.() do
      assert remaining > 0
      Process.sleep(10)
      await(check, remaining - 1)
    end
  end
end
