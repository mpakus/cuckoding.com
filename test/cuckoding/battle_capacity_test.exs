defmodule Cuckoding.BattleCapacityTest do
  use Cuckoding.DataCase

  alias Cuckoding.{
    BattleRunner,
    Battles,
    Codex,
    ExecutionSupervisor,
    Foundation,
    Tabulae,
    Team,
    TeamAssignments
  }

  alias Cuckoding.Battles.{Attempt, Battle, ProviderClosure, Snapshot}

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

    %{board: board}
  end

  defp board do
    arena = Cuckoding.DataCase.arena_fixture()
    {:ok, board} = Tabulae.create(Ecto.UUID.generate(), arena.id, "Another Arena")
    board
  end

  defp start(board) do
    {:ok, _} =
      Tabulae.save(Ecto.UUID.generate(), board.arena_id, board.id, Ecto.UUID.generate(), 0, %{
        "title" => "Independent task",
        "description" => "Implement locally",
        "criteria" => "Inspect the result",
        "column" => "specs"
      })

    {:ok, preview} = Battles.preview(board.arena_id, board.id)
    assert preview.blockers == []

    {:ok, battle} =
      Battles.start(Ecto.UUID.generate(), board.arena_id, board.id, preview.fingerprint, true)

    battle
  end

  defp finish_native(attempt) do
    receipt = native_receipt(attempt)
    {:ok, battle} = Battles.finish(attempt.id, attempt.claim_token, receipt)
    battle
  end

  defp native_receipt(attempt) do
    payload =
      case attempt.stage do
        "admission" ->
          %{
            "status" => "admitted",
            "head" => String.duplicate("a", 40),
            "native_battle" => %{},
            "resolved_checks" => []
          }

        "prepare_worktree" ->
          %{"status" => "prepared", "preparation" => %{}}
      end

    Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))
    |> Map.merge(payload)
    |> Map.put("cleanup_verified", true)
  end

  defp runner do
    parent = self()

    executor = fn attempt ->
      send(parent, {:launched, self(), attempt})

      receive do
        :finish -> native_receipt(attempt)
        :crash -> exit(:fixture_failure)
      end
    end

    start_supervised!(
      {ExecutionSupervisor,
       coordinator: BattleRunner, tasks: Cuckoding.BattleTasks, options: [executor: executor]}
    )

    Process.whereis(BattleRunner)
  end

  defp await(check, remaining \\ 200) do
    if not check.() do
      assert remaining > 0
      Process.sleep(10)
      await(check, remaining - 1)
    end
  end

  test "new Starts freeze isolated Arena concurrency", ctx do
    assert start(ctx.board).snapshot["scheduler"] == "isolated-arenas-v1"
  end

  test "only a recorded exact provider closure releases interrupted connection capacity", ctx do
    first = start(ctx.board)
    second = start(board())

    for battle <- [first, second] do
      {:ok, admission} = Battles.claim_next(battle.id)
      finish_native(admission)
      {:ok, prepare} = Battles.claim_next(battle.id)
      finish_native(prepare)
    end

    {:ok, attempt} = Battles.claim_next(first.id)
    {:ok, _} = Battles.recover()
    interrupted = Repo.get!(Attempt, attempt.id)
    # The other clean Arena pauses at restart; continue it explicitly.
    paused = Battles.get(second.id)
    assert {:ok, resumed} = Battles.resume(paused.id, paused.control_revision)
    assert {:error, :capacity} = Battles.claim_next(second.id)

    native =
      ProviderClosure.binding_for(interrupted)
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

    result = Cuckoding.BattleExecutor.reconcile_provider(interrupted, fn _, _ -> native end)
    assert {:ok, observed} = Battles.reconcile_provider(interrupted, result)
    assert {:ok, next} = Battles.claim_next(resumed.id)
    assert next.role == "summa_rudis"
    assert Repo.get!(Attempt, attempt.id) == interrupted
    assert observed.state == "needs_attention"
  end

  test "concurrent database claims cannot exceed two global battle workers", ctx do
    battles = [start(ctx.board) | Enum.map(1..5, fn _ -> start(board()) end)]
    claims = battles |> Task.async_stream(&Battles.claim_next(&1.id)) |> Enum.map(&elem(&1, 1))
    assert Enum.count(claims, &match?({:ok, %Attempt{}}, &1)) == 2
    assert Enum.count(claims, &(&1 == {:error, :capacity})) == 4
    assert Repo.aggregate(from(a in Attempt, where: a.state == "running"), :count) == 2

    for battle <- battles, Battles.attempts(battle.id) == [] do
      assert Battles.get(battle.id).turns_used == 0
      assert length(Battles.evidence(battle.id)) == 1
    end
  end

  test "a shared connection queues its next provider stage without spending turns or retries",
       ctx do
    first = start(ctx.board)
    second = start(board())

    for battle <- [first, second] do
      {:ok, admission} = Battles.claim_next(battle.id)
      finish_native(admission)
      {:ok, prepare} = Battles.claim_next(battle.id)
      finish_native(prepare)
    end

    {:ok, _} = Battles.claim_next(first.id)
    before = Battles.get(second.id)
    assert {:error, :capacity} = Battles.claim_next(second.id)
    assert Battles.get(second.id) == before
    assert before.context["provider_retries"] == nil
    refute Enum.any?(Battles.attempts(second.id), &(&1.state == "running"))
  end

  test "uncertain provider cleanup keeps that exact connection reserved across Arenas", ctx do
    first = start(ctx.board)
    second = start(board())

    for battle <- [first, second] do
      {:ok, admission} = Battles.claim_next(battle.id)
      finish_native(admission)
      {:ok, prepare} = Battles.claim_next(battle.id)
      finish_native(prepare)
    end

    {:ok, active} = Battles.claim_next(first.id)

    receipt =
      Map.take(active.request, ~w(battle_id request_id task_id stage criteria_sha256))
      |> Map.merge(%{
        "status" => "failed",
        "reason" => "connection_lost",
        "provider" => %{"status" => "connection_lost"},
        "cleanup_verified" => false
      })

    {:ok, failed} = Battles.finish(active.id, active.claim_token, receipt)
    assert failed.state == "needs_attention"
    assert {:error, :capacity} = Battles.claim_next(second.id)
    assert length(Battles.attempts(second.id)) == 2
  end

  test "historical Starts preserve exclusive global dispatch in either direction", ctx do
    original = start(ctx.board)
    {:ok, _} = Battles.stop(original.id)
    snapshot = Map.delete(original.snapshot, "scheduler")

    legacy =
      Repo.insert!(%Battle{
        id: Ecto.UUID.generate(),
        arena_id: original.arena_id,
        tabula_id: original.tabula_id,
        snapshot: snapshot,
        fingerprint: Snapshot.digest(snapshot),
        state: "running",
        stage: "admission",
        deadline_at: original.deadline_at
      })

    for {task, position} <- Enum.with_index(snapshot["tasks"]) do
      Repo.insert!(%Cuckoding.Battles.Task{
        id: Ecto.UUID.generate(),
        battle_id: legacy.id,
        task_id: task["id"],
        position: position,
        snapshot: task
      })
    end

    newer = start(board())
    {:ok, active} = Battles.claim_next(newer.id)
    assert {:error, :capacity} = Battles.claim_next(legacy.id)
    finish_native(active)
    {:ok, _} = Battles.claim_next(legacy.id)
    assert {:error, :capacity} = Battles.claim_next(newer.id)
    assert length(Battles.attempts(legacy.id)) == 1
  end

  test "two supervised workers run independently and a third Arena gets the next free slot",
       ctx do
    runner = runner()
    battles = [start(ctx.board), start(board()), start(board())]
    [first, second, third] = battles
    send(runner, :poll)
    assert_receive {:launched, worker1, attempt1}, 1_000
    assert_receive {:launched, worker2, attempt2}, 1_000

    assert MapSet.new([attempt1.battle_id, attempt2.battle_id]) ==
             MapSet.new([first.id, second.id])

    assert length(Task.Supervisor.children(Cuckoding.BattleTasks)) == 2
    for _ <- 1..20, do: send(runner, :poll)
    refute_receive {:launched, _, _}, 50
    assert map_size(:sys.get_state(runner).jobs) == 2
    send(worker1, :finish)
    assert_receive {:launched, worker3, attempt3}, 1_000
    assert attempt3.battle_id == third.id
    assert attempt3.stage == "admission"
    assert Battles.get(attempt1.battle_id).stage == "prepare_worktree"
    assert Repo.get!(Attempt, attempt1.id).state == "completed"

    for battle <- battles do
      current = Battles.get(battle.id)
      {:ok, _} = Battles.pause(battle.id, current.control_revision)
    end

    send(worker2, :finish)
    send(worker3, :finish)
    await(fn -> Enum.all?(battles, &(Battles.get(&1.id).state == "paused")) end)
    await(fn -> :sys.get_state(runner).jobs == %{} end)
  end

  test "one failed worker does not cancel another Arena", ctx do
    runner = runner()
    first = start(ctx.board)
    second = start(board())
    send(runner, :poll)
    assert_receive {:launched, worker1, attempt1}, 1_000
    assert_receive {:launched, worker2, attempt2}, 1_000

    assert MapSet.new([attempt1.battle_id, attempt2.battle_id]) ==
             MapSet.new([first.id, second.id])

    send(worker1, :crash)
    await(fn -> Battles.get(attempt1.battle_id).state == "needs_attention" end)
    assert Process.alive?(worker2)
    assert Process.whereis(BattleRunner) == runner
    assert Battles.get(attempt2.battle_id).state == "running"
    assert Repo.get!(Attempt, attempt1.id).result["cleanup_verified"] == false
    {:ok, _} = Battles.pause(attempt2.battle_id, 0)
    send(worker2, :finish)
    await(fn -> Battles.get(attempt2.battle_id).state == "paused" end)
  end

  test "coordinator restart stops every old worker before recovery and never replays claims",
       ctx do
    runner = runner()
    first = start(ctx.board)
    second = start(board())
    send(runner, :poll)
    assert_receive {:launched, worker1, attempt1}, 1_000
    assert_receive {:launched, worker2, attempt2}, 1_000
    Process.exit(runner, :kill)

    await(fn ->
      Enum.all?([first, second], &(Battles.get(&1.id).state == "needs_attention")) and
        Process.whereis(BattleRunner) != runner
    end)

    refute Process.alive?(worker1)
    refute Process.alive?(worker2)

    for attempt <- [attempt1, attempt2] do
      assert Repo.get!(Attempt, attempt.id).state == "interrupted"
      assert length(Battles.attempts(attempt.battle_id)) == 1
      assert {:error, :cleanup_required} = Battles.stop(attempt.battle_id)
    end

    refute_receive {:launched, _, _}, 100
  end
end
