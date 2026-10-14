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

  alias Cuckoding.Battles.Attempt

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

  defp start(board) do
    {:ok, preview} = Battles.preview(board.arena_id, board.id)
    assert preview.blockers == []

    {:ok, battle} =
      Battles.start(Ecto.UUID.generate(), board.arena_id, board.id, preview.fingerprint, true)

    battle
  end

  defp step(battle) do
    {:ok, attempt} = Battles.claim_next(battle.id)
    result = BattleExecutor.execute(attempt, git: Adapters, provider: Adapters, checks: Adapters)
    assert {:ok, next} = Battles.finish(attempt.id, attempt.claim_token, result)
    {next, attempt, result}
  end

  defp drive(battle, remaining \\ 60)
  defp drive(%{state: "completed"} = battle, _), do: battle

  defp drive(battle, remaining) when remaining > 0 do
    assert battle.state == "running", inspect(battle.reason)
    {battle, _, _} = step(battle)
    drive(battle, remaining - 1)
  end

  defp until_stage(battle, stage) do
    if battle.stage == stage, do: battle, else: until_stage(elem(step(battle), 0), stage)
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

  test "runner records invalid receipt failure and closes admission without replay", %{
    board: board
  } do
    unless Process.whereis(Cuckoding.BattleTasks),
      do: start_supervised!({Task.Supervisor, name: Cuckoding.BattleTasks})

    test = self()

    executor = fn attempt ->
      send(test, {:stage_launched, attempt.id})
      %{"status" => "admitted", "cleanup_verified" => false}
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

  test "runner settles a pausing stage once and survives restart at the paused boundary", %{
    board: board
  } do
    start_supervised!({Task.Supervisor, name: Cuckoding.BattleTasks})
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
    start_supervised!({Task.Supervisor, name: Cuckoding.BattleTasks})
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
