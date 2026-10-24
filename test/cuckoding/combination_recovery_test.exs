defmodule Cuckoding.CombinationRecoveryTest do
  use Cuckoding.DataCase
  import Cuckoding.BattleFixtures
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  @endpoint CuckodingWeb.Endpoint
  alias Cuckoding.{ArenaGit, Arenas, BattleExecutor, BattleRunner, Battles, ExecutionSupervisor}
  alias Cuckoding.Battles.{Attempt, CandidateRecovery, MixedClosure}

  defmodule ReadGit do
    def run(%{id: id, payload: payload}, options) do
      true = options[:active?].()
      "recover_combined_candidate" = payload["operation"]
      request = payload["request"]
      true = Map.keys(request) |> Enum.sort() == ~w(battle candidate key preparation)
      ^id = request["key"]

      receipt = %{
        "status" => "candidate_combined",
        "key" => id,
        "battle_key" => request["battle"]["battle_key"],
        "worktree_key" => request["preparation"]["key"],
        "task_candidate_key" => request["candidate"]["key"],
        "base" => request["battle"]["head"],
        "task_base" => request["preparation"]["head"],
        "candidate" => Base.encode16(:crypto.hash(:sha, id), case: :lower),
        "tree" => String.duplicate("a", 40),
        "manifest_sha256" => String.duplicate("b", 64)
      }

      if Process.get(:unverified_combination),
        do: Map.put(receipt, "cleanup_verified", false),
        else: receipt
    end
  end

  setup do
    ctx = fixture()
    root = "/private/tmp/cuckoding-combination-recovery-#{Ecto.UUID.generate()}"
    File.mkdir_p!(root)
    home = Application.get_env(:cuckoding, :discovery_home)
    Application.put_env(:cuckoding, :discovery_home, root <> "-home")

    on_exit(fn ->
      Application.put_env(:cuckoding, :discovery_home, home)
      File.rm_rf!(root)
    end)

    {:ok, folder} = Arenas.inspect_folder(root)
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

  defp combined(board, omitted \\ []) do
    save_task(board, "Independent", [])
    battle = if omitted == [], do: start(board), else: start_legacy(board, omitted)
    attempt = claim_combination(battle, 80)
    {:ok, _} = Battles.recover()
    {Battles.get(battle.id), Repo.get!(Attempt, attempt.id)}
  end

  defp claim_combination(battle, left) do
    assert left > 0
    {:ok, attempt} = Battles.claim_next(battle.id)

    if attempt.stage == "combine" do
      attempt
    else
      {:ok, next} = Battles.finish(attempt.id, attempt.claim_token, stage_result(attempt))
      claim_combination(next, left - 1)
    end
  end

  defp observation(attempt), do: result(attempt, %{"status" => "combined"})

  defp stage_result(attempt) do
    context = attempt.request["task_context"]
    head = attempt.request["context"]["head"]

    override =
      case attempt.stage do
        "admission" ->
          %{
            "native_battle" => %{
              "status" => "battle_created",
              "key" => attempt.battle_id,
              "battle_key" => attempt.battle_id,
              "base" => String.duplicate("a", 40),
              "head" => String.duplicate("a", 40),
              "reference" => "refs/heads/ccoding/battles/" <> attempt.battle_id,
              "manifest_sha256" => String.duplicate("b", 64)
            }
          }

        "prepare_worktree" ->
          %{
            "preparation" => %{
              "key" => attempt.id,
              "head" => head,
              "path" => ArenaGit.worktree_path(attempt.id),
              "device" => 1,
              "inode" => 2
            }
          }

        "capture" ->
          %{
            "native_candidate" => %{
              "status" => "candidate_captured",
              "key" => attempt.id,
              "worktree_key" => context["preparation"]["key"],
              "base" => context["preparation"]["head"],
              "candidate" => Base.encode16(:crypto.hash(:sha, attempt.id), case: :lower),
              "tree" => String.duplicate("a", 40),
              "manifest_sha256" => String.duplicate("b", 64)
            }
          }

        "integrate" ->
          %{
            "native_battle" =>
              Map.merge(attempt.request["context"]["native_battle"], %{
                "status" => "battle_integrated",
                "key" => attempt.id,
                "previous_head" => head,
                "head" => context["candidate_sha"],
                "candidate_key" => context["native_candidate"]["key"]
              })
          }

        _ ->
          %{}
      end

    result(attempt, override)
  end

  test "complete retained combination pauses for fresh checks/review without changing its claim",
       ctx do
    {battle, attempt} = combined(ctx.board)
    assert battle.snapshot["combination_recovery"] == "retained-combination-v1"
    assert Battles.recovery_attempt() == attempt
    old_task = Enum.find(Battles.tasks(battle.id), &(&1.task_id == attempt.task_id))
    assert old_task.context["native_candidate"]["status"] == "candidate_captured"
    receipt = BattleExecutor.reconcile_combination(attempt, git: ReadGit)
    assert receipt == observation(attempt)
    {:ok, paused} = Battles.reconcile_recovery(attempt, receipt)
    assert paused.state == "paused" and paused.stage == "checks"
    assert paused.context["head"] == battle.context["head"]
    assert paused.turns_used == battle.turns_used and paused.deadline_at == battle.deadline_at
    task = Enum.find(Battles.tasks(battle.id), &(&1.task_id == attempt.task_id))
    assert task.context["native_candidate"] == receipt["native_candidate"]
    refute task.context["checks"]
    refute task.context["provider"]
    assert task.review_round == old_task.review_round
    assert task.context["provider_retries"] == old_task.context["provider_retries"]
    assert Repo.get!(Attempt, attempt.id) == attempt
    assert {:error, :stale_reconciliation} = Battles.reconcile_recovery(attempt, receipt)
    {:ok, resumed} = Battles.resume(paused.id, paused.control_revision)
    {:ok, next} = Battles.claim_next(resumed.id)
    assert next.stage == "checks" and next.task_id == attempt.task_id
    assert next.request["task_context"]["candidate_sha"] == receipt["candidate_sha"]
    assert next.request["context"]["head"] == battle.context["head"]
  end

  test "old policies never gain combination recovery or cleanup authority", ctx do
    {battle, attempt} = combined(ctx.board, ["combination_recovery"])
    refute Battles.recovery_attempt()
    refute CandidateRecovery.pending?(battle, attempt)

    assert {:error, :stale_reconciliation} =
             Battles.reconcile_recovery(attempt, observation(attempt))

    assert {:error, :cleanup_required} = Battles.stop(battle.id)
  end

  test "Resume revalidates exact saved bindings after the recovered checkpoint", ctx do
    {battle, attempt} = combined(ctx.board)
    {:ok, paused} = Battles.reconcile_recovery(attempt, observation(attempt))
    workspace = Cuckoding.Foundation.workspace()

    Repo.update!(
      Ecto.Changeset.change(workspace,
        connection: Map.put(workspace.connection, "authorization", "not_connected")
      )
    )

    assert {:error, :resume_binding_changed} = Battles.resume(battle.id, paused.control_revision)
    assert Battles.get(battle.id) == paused
    assert Repo.get!(Attempt, attempt.id) == attempt
  end

  test "foreign, malformed and unverified proof cannot settle the original attempt", ctx do
    {battle, attempt} = combined(ctx.board)
    good = observation(attempt)

    for path <- [
          ["request_id"],
          ["task_id"],
          ["battle_id"],
          ["native_candidate", "key"],
          ["native_candidate", "worktree_key"],
          ["native_candidate", "task_candidate_key"]
        ] do
      bad = put_in(good, path, Ecto.UUID.generate())
      assert {:error, reason} = Battles.reconcile_recovery(attempt, bad)
      assert reason in [:foreign_result, :invalid_result]
    end

    for bad <- [
          Map.put(good, "cleanup_verified", false),
          Map.put(good, "raw", "PRIVATE_CANARY"),
          put_in(good, ["native_candidate", "base"], String.duplicate("f", 40))
        ] do
      assert {:error, reason} = Battles.reconcile_recovery(attempt, bad)
      assert reason in [:foreign_result, :invalid_result]
    end

    assert Battles.recovery_attempt() == attempt
    Process.put(:unverified_combination, true)
    failed = BattleExecutor.reconcile_combination(attempt, git: ReadGit)
    Process.delete(:unverified_combination)
    assert failed["status"] == "failed" and failed["cleanup_verified"] == false
    {:ok, retained} = Battles.reconcile_recovery(attempt, failed)
    assert retained.state == "needs_attention"
    assert Repo.get!(Attempt, attempt.id) == attempt
    assert {:error, :cleanup_required} = Battles.stop(battle.id)
    refute Battles.recovery_attempt()
  end

  test "late or timing-fenced verified observations permit Stop only", ctx do
    {battle, attempt} = combined(ctx.board)
    tasks = Battles.tasks(battle.id)
    {:ok, late} = Battles.reconcile_candidate(attempt, observation(attempt), attempt.deadline_at)
    assert late.state == "needs_attention" and late.reason == "late_result_rejected"
    assert Battles.tasks(battle.id) == tasks
    assert {:error, _} = Battles.resume(battle.id, late.control_revision)
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)

    {battle, attempt} = combined(ctx.board)
    tasks = Battles.tasks(battle.id)

    gap =
      Cuckoding.BattleClock.gap(
        {DateTime.utc_now(), 0},
        {DateTime.add(DateTime.utc_now(), -60), 1000}
      )

    {:ok, _} = Battles.observe_timing_gap(gap)
    refute Battles.candidate_reconciliation_current?(attempt)
    {:ok, fenced} = Battles.reconcile_recovery(attempt, observation(attempt))
    assert fenced.reason == "timing_gap" and fenced.state == "needs_attention"
    assert Battles.tasks(battle.id) == tasks
    assert {:ok, %{state: "stopped"}} = Battles.stop(battle.id)
  end

  test "single-combination admission cannot extend mixed or historical recovery policies", ctx do
    {battle, attempt} = combined(ctx.board)
    running = %{battle | state: "running"}
    assert CandidateRecovery.eligible?(running, [attempt])

    refute CandidateRecovery.eligible?(running, [
             attempt,
             %{
               attempt
               | id: Ecto.UUID.generate(),
                 stage: "capture",
                 task_id: Ecto.UUID.generate()
             }
           ])

    refute MixedClosure.member?(battle, attempt)

    for state <- ~w(stopping stopped paused needs_attention) do
      refute CandidateRecovery.eligible?(%{running | state: state}, [attempt])
    end

    for field <- ~w(combination_recovery candidate_recovery parallelism) do
      snapshot = Map.delete(running.snapshot, field)

      refute CandidateRecovery.eligible?(%{running | snapshot: snapshot}, [
               %{attempt | request: Map.put(attempt.request, "snapshot", snapshot)}
             ])
    end
  end

  test "an audited event failure rolls back recovery and leaves its read pending", ctx do
    {battle, attempt} = combined(ctx.board)

    Repo.query!("""
    CREATE TEMP TRIGGER refuse_combination_recovery BEFORE INSERT ON events
    WHEN NEW.kind = 'battle.candidate_reconciled'
    BEGIN SELECT RAISE(ABORT, 'fixture refuses recovery'); END
    """)

    try do
      assert_raise Exqlite.Error, fn ->
        Battles.reconcile_recovery(attempt, observation(attempt))
      end

      assert Battles.get(battle.id) == battle
      assert Repo.get!(Attempt, attempt.id) == attempt
      assert Battles.recovery_attempt() == attempt
    after
      Repo.query!("DROP TRIGGER refuse_combination_recovery")
    end
  end

  test "supervised recovery survives coordinator loss without replaying combination or inference",
       ctx do
    {battle, attempt} = combined(ctx.board)
    owner = self()

    reconciler = fn current ->
      send(owner, {:combination_read, self(), current})

      receive do
        :inspect -> BattleExecutor.reconcile_combination(current, git: ReadGit)
      end
    end

    start_supervised!(
      {ExecutionSupervisor,
       coordinator: BattleRunner,
       tasks: Cuckoding.BattleTasks,
       options: [
         reconciler: reconciler,
         executor: fn current -> send(owner, {:unexpected_stage, current}) end
       ]}
    )

    assert_receive {:combination_read, worker, ^attempt}, 1000
    monitor = Process.monitor(worker)
    Process.exit(Process.whereis(BattleRunner), :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :shutdown}, 1000
    assert_receive {:combination_read, replacement, ^attempt}, 1000
    send(replacement, :inspect)
    await_paused(battle.id, System.monotonic_time(:millisecond) + 2000)
    assert Repo.get!(Attempt, attempt.id) == attempt

    assert Enum.count(Battles.evidence(battle.id), &(&1.kind == "battle.candidate_reconciled")) ==
             1

    refute_receive {:unexpected_stage, _}
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

  test "the existing LiveView shows retained combination, reconnects and resumes explicitly",
       ctx do
    {battle, attempt} = combined(ctx.board)
    path = "/arenas/#{ctx.board.arena_id}/tabulae/#{ctx.board.id}"
    signed = CuckodingWeb.ConnCase.local_conn() |> CuckodingWeb.ConnCase.sign_in()
    {:ok, view, _} = live(signed, path)
    assert has_element?(view, "#battle-candidate-inspecting", "No combination")
    refute has_element?(view, "#battle-resume")
    {:ok, paused} = Battles.reconcile_recovery(attempt, observation(attempt))
    selector = "#battle-candidate-reconciliation-#{attempt.id}"
    assert has_element?(view, selector, "fresh checks")
    assert has_element?(view, "#battle-recovery-status", "Paused after restart")
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, selector, "fresh checks")
    assert has_element?(again, "#battle-resume", "Resume")
    assert Battles.get(battle.id) == paused
    again |> element("#battle-resume") |> render_click()
    assert Battles.get(battle.id).state == "running"
    assert Repo.get!(Attempt, attempt.id) == attempt
  end
end
