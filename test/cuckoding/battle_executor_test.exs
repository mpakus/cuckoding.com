defmodule Cuckoding.BattleExecutorTest do
  use Cuckoding.DataCase

  alias Cuckoding.{
    ArenaGit,
    Arenas,
    BattleExecutor,
    BattleRunner,
    Battles,
    Codex,
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

    def resolve(checks),
      do: {:ok, Enum.map(checks, &Map.merge(&1, %{"identity" => %{}, "rtk_identity" => %{}}))}

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

      %{
        "status" => "task_finished",
        "request_id" => request["request_id"],
        "requested_model" => request["model"],
        "observed_model" => Process.get(:observed_model, request["model"]),
        "effort" => request["effort"],
        "grant" => "host-task-tools-v1",
        "access" => request["access"],
        "thread_id" => Ecto.UUID.generate(),
        "turn_id" => Ecto.UUID.generate(),
        "report" => %{"outcome" => outcome, "summary" => summary(prompt["stage"], outcome)},
        "tools" => tools,
        "changes" => changes
      }
    end

    defp outcome(prompt) do
      cond do
        Process.get(:invalid_outcome_stage) == prompt["stage"] ->
          "changes_requested"

        prompt["stage"] in ~w(secutor final_secutor) and
            Enum.any?(prompt["host_checks"] || [], &(&1["status"] != "passed")) ->
          "changes_requested"

        true ->
          "completed"
      end
    end

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
