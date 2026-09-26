defmodule Cuckoding.BoardControlTest do
  use CuckodingWeb.ConnCase, async: false
  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuckoding.{BoardControl, ProjectWorkflow, Repo, RunControl, WalkingSkeleton, Workflows}
  alias Cuckoding.Execution.{Environment, GitService, Run}

  defmodule GateResult do
    def result(handle) do
      with {:ok, result} <- Cuckoding.Execution.LocalProcessRunner.result(handle),
           do: {:ok, Map.put(result, :adapter, "fake")}
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "board-control-#{System.unique_integer([:positive])}")
    repo = Path.join(root, "repo")
    File.mkdir_p!(repo)
    git!(repo, ["init", "-b", "main"])
    git!(repo, ["config", "user.email", "tests@cuckoding.local"])
    git!(repo, ["config", "user.name", "Cuckoding Tests"])
    File.write!(Path.join(repo, "README.md"), "# Board control\n")
    git!(repo, ["add", "."])
    git!(repo, ["commit", "-m", "Initial"])
    previous = Application.get_env(:cuckoding, :workspace_root)
    Application.put_env(:cuckoding, :workspace_root, Path.join(root, "workspaces"))

    {:ok, skeleton} =
      WalkingSkeleton.create(%{
        name: "Control",
        repo_path: repo,
        workspace_root: Path.join(root, "workspaces"),
        task_title: "Fixture setup",
        start_run: false
      })

    {:ok, _} = RunControl.control(skeleton.run.id, "stop")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cuckoding, :workspace_root, previous),
        else: Application.delete_env(:cuckoding, :workspace_root)

      File.rm_rf!(root)
    end)

    %{board: skeleton.board, project: skeleton.project}
  end

  test "fixed mixed batch hands reviewed commits to the next task and finishes", %{
    board: board,
    project: project
  } do
    first = task(board.id, "First reviewed change", 1)
    second = task(board.id, "Dependent high priority change", 9)
    {:ok, _} = Workflows.transition_task(second.id, "ready", "ready-second")
    assert {:ok, _} = Workflows.add_dependency(second.id, first.id)
    {:ok, preview} = BoardControl.preflight(board.id)
    {:ok, batch} = BoardControl.start(board.id, preview.digest, [], "start", true)
    assert {:ok, replay} = BoardControl.start(board.id, preview.digest, [], "start", true)
    assert replay.id == batch.id
    late = task(board.id, "Next batch", 99)
    assert {:ok, %{task_id: id}} = BoardControl.next_item(batch)
    assert id == first.id
    assert {:error, :board_owned} = ProjectWorkflow.prepare_task(second.id)
    dispatch()

    assert %{phase: "delivery", current_task_id: id, state: "running"} =
             BoardControl.get(batch.id)

    assert id == first.id
    dispatch()

    assert BoardControl.get(batch.id).state == "running",
           inspect(BoardControl.get(batch.id).issue)

    assert [first_run] = Cuckoding.Execution.list_runs(first.id)
    assert first_run.state == "done"
    dispatch()
    reviewed = BoardControl.get(batch.id).head_sha
    refute reviewed == batch.base_sha
    dispatch()
    assert BoardControl.get(batch.id).current_task_id == second.id
    dispatch()
    assert [second_run] = Cuckoding.Execution.list_runs(second.id)
    assert second_run.state == "done"
    assert second_run.base_sha == reviewed
    env = Repo.get_by!(Environment, run_id: second_run.id)
    assert {:ok, _} = GitService.inspect(env)

    assert git!(env.worktree_path, ["show", "#{second_run.base_sha}:WALKING_SKELETON.md"]) =~
             first.title

    dispatch()
    dispatch()
    assert BoardControl.get(batch.id).state == "done"
    assert Cuckoding.Execution.list_runs(late.id) == []
    assert {:ok, base} = GitService.capture_base(project)
    assert base == batch.base_sha
    assert Enum.all?(BoardControl.items(batch.id), &(&1.state == "done"))
  end

  test "external prerequisites require reviewed code in the captured project base", %{
    board: board,
    project: project
  } do
    prerequisite = task(board.id, "Previously reviewed work", 1)
    batch = start(board.id)
    for _ <- 1..4, do: dispatch()
    completed = BoardControl.get(batch.id)
    assert completed.state == "done"
    dependent = task(board.id, "New dependent batch", 2)
    {:ok, _} = Workflows.add_dependency(dependent.id, prerequisite.id)
    assert {:error, :dependency_code_unavailable} = BoardControl.preflight(board.id)

    git!(project.repo_path, ["merge", "--ff-only", completed.head_sha])
    assert {:ok, preview} = BoardControl.preflight(board.id)
    assert preview.snapshot["base_sha"] == completed.head_sha
    assert Enum.map(preview.tasks, & &1["id"]) == [dependent.id]
  end

  test "closed decision contract rejects forged order, stale revision and extra grants" do
    input = %{"execution_id" => "batch", "revision" => 2, "next_task_id" => "next"}
    output = BoardControl.Decision.fake_output(input)
    assert :ok = BoardControl.Decision.validate(output, input, %{task_id: "next"})

    for invalid <- [
          Map.put(output, "task_id", "other"),
          Map.put(output, "revision", 1),
          Map.put(output, "revision", 2.0),
          Map.put(output, "permissions", ["write"])
        ] do
      assert {:error, :invalid_controller_output} =
               BoardControl.Decision.validate(invalid, input, %{task_id: "next"})
    end
  end

  test "pause closes admission, stale commands fail, skip defers descendants and retains history",
       %{board: board} do
    first = task(board.id, "Skip prerequisite", 9)
    dependent = task(board.id, "Deferred descendant", 10)
    independent = task(board.id, "Independent", 1)
    {:ok, _} = Workflows.add_dependency(dependent.id, first.id)
    batch = start(board.id)
    dispatch()
    selected = BoardControl.get(batch.id)
    assert selected.current_task_id == first.id
    assert {:ok, paused} = BoardControl.control(batch.id, selected.revision, "pause", "pause")
    assert paused.state == "paused"
    dispatch()
    assert Cuckoding.Execution.list_runs(first.id) == []

    assert {:error, "stale_execution"} =
             BoardControl.control(batch.id, selected.revision, "resume", "stale")

    assert {:ok, resumed} = BoardControl.control(batch.id, paused.revision, "resume", "resume")

    assert {:error, "confirmation_required"} =
             BoardControl.control(batch.id, resumed.revision, "skip", "unconfirmed")

    assert {:ok, skipped} =
             BoardControl.control(batch.id, resumed.revision, "skip", "skip", confirmed: true)

    assert skipped.head_sha == batch.head_sha
    outcomes = Map.new(BoardControl.items(batch.id), &{&1.task_id, &1.state})

    assert outcomes == %{
             first.id => "skipped",
             dependent.id => "deferred",
             independent.id => "pending"
           }

    for _ <- 1..4, do: dispatch()
    assert BoardControl.get(batch.id).state == "finished_with_skips"
    refute Workflows.get_task(first.id).state == "done"
    assert Workflows.get_task(independent.id).state == "done"
  end

  test "capacity waits without invoking the controller and resumes when capacity returns", %{
    board: board
  } do
    task(board.id, "Wait", 1)
    batch = start(board.id)

    for _ <- 1..2 do
      BoardControl.dispatch_once(
        resource_probe: %{
          memory_available_bytes: fn -> {:ok, 0} end,
          available_ports: fn _ -> {:ok, 10} end
        }
      )
    end

    assert BoardControl.get(batch.id).state == "waiting"
    assert Cuckoding.Execution.list_runs(batch.controller_task_id) == []
    dispatch()
    assert BoardControl.get(batch.id).phase == "delivery"
  end

  test "lost controller worker requires attention and explicit retry retains the previous attempt",
       %{board: board} do
    task(board.id, "Recover", 1)
    batch = start(board.id)
    {:ok, _} = Workflows.transition_task(batch.controller_task_id, "ready", "controller-ready")

    {:ok, prepared} =
      ProjectWorkflow.prepare_task(batch.controller_task_id, board_execution_id: batch.id)

    {:ok, _} = Cuckoding.Execution.transition_run(prepared.run.id, "running", "lost-worker")
    dispatch()
    blocked = BoardControl.get(batch.id)
    assert blocked.state == "attention"
    assert blocked.issue == "worker_unavailable"
    assert {:ok, retried} = BoardControl.control(batch.id, blocked.revision, "retry", "retry")
    assert retried.state == "running"
    dispatch()
    assert BoardControl.get(batch.id).phase == "delivery"
    assert length(Cuckoding.Execution.list_runs(batch.controller_task_id)) == 2
    assert Repo.get!(Run, prepared.run.id).state == "cancelled"
  end

  test "start modal requires local-completion consent and dashboard shows the full batch", %{
    board: board,
    conn: conn
  } do
    task(board.id, "Visible batch task", 3)
    {:ok, view, _} = live(conn, ~p"/boards/#{board.id}")
    view |> element("#start-board-button") |> render_click()
    assert has_element?(view, "#start-board-modal", "Visible batch task")
    render_submit(view, "start-board", %{"batch" => %{}})
    assert has_element?(view, "#start-board-modal [role=alert]", "consent")
    view |> element("button[phx-click=close-task-modal]") |> render_click()
    view |> element("#start-board-button") |> render_click()
    view |> form("#start-board-form", batch: %{consent: "true"}) |> render_submit()
    refute has_element?(view, "#start-board-modal")
    batch = BoardControl.current(board.id)
    assert has_element?(view, "#board-control-#{batch.id}", "Included")
    assert has_element?(view, "#board-pause")
    {:ok, dashboard, _} = live(conn, ~p"/")
    assert has_element?(dashboard, "#board-control-#{batch.id}", "Open board controls")
    view |> element("#board-stop") |> render_click()
    assert has_element?(view, "#board-control-confirmation")
    view |> element("button[phx-click=confirm-board-control]") |> render_click()
    assert BoardControl.get(batch.id).state == "stopped"
  end

  test "invalid controller output halts without delivery; skip during decision continues independent work",
       %{board: board} do
    first = task(board.id, "Invalid proposal", 9)
    second = task(board.id, "Independent after exclusion", 1)
    batch = start(board.id)
    dispatch(fake_decision: %{"action" => "push", "summary" => "Expand permissions"})
    blocked = BoardControl.get(batch.id)
    assert blocked.state == "attention"
    assert blocked.issue == "invalid_controller_output"
    assert Cuckoding.Execution.list_runs(first.id) == []

    assert {:ok, _} =
             BoardControl.control(batch.id, blocked.revision, "skip", "skip-invalid",
               confirmed: true
             )

    for _ <- 1..4, do: dispatch()
    assert Workflows.get_task(second.id).state == "done"
    assert BoardControl.get(batch.id).state == "finished_with_skips"
  end

  test "pending edits require reviewed refresh and Git drift keeps admission closed", %{
    board: board,
    project: project
  } do
    task = task(board.id, "Original request", 1)
    batch = start(board.id)
    task |> Ecto.Changeset.change(title: "Reviewed updated request") |> Repo.update!()
    dispatch()
    blocked = BoardControl.get(batch.id)
    assert blocked.issue == "stale_task_snapshot"

    assert {:error, :stale_task_snapshot} =
             BoardControl.control(batch.id, blocked.revision, "refresh", "stale-refresh",
               confirmed: true,
               expected_snapshot: []
             )

    assert {:ok, refreshed} =
             BoardControl.control(batch.id, blocked.revision, "refresh", "refresh",
               confirmed: true,
               expected_snapshot: BoardControl.pending_requests(batch.id)
             )

    assert {:ok, resumed} =
             BoardControl.control(batch.id, refreshed.revision, "resume", "resume-refresh")

    assert resumed.state == "running"
    File.write!(Path.join(project.repo_path, "drift.txt"), "unreviewed")
    dispatch()
    assert BoardControl.get(batch.id).state == "attention"
    assert Cuckoding.Execution.list_runs(task.id) == []
  end

  test "all batch sessions contribute once and missing measurements remain unavailable", %{
    board: board
  } do
    task(board.id, "Accounting", 1)
    batch = start(board.id)
    dispatch()
    [controller] = Cuckoding.Execution.list_runs(batch.controller_task_id)
    attempt = Repo.get_by!(Cuckoding.Execution.StageAttempt, run_id: controller.id)

    for index <- 1..105 do
      {:ok, session} =
        Cuckoding.Execution.create_agent_session(%{
          stage_attempt_id: attempt.id,
          adapter_key: "fake",
          effective_grant_json: %{}
        })

      usage = %Cuckoding.Adapters.Types.Usage{
        source: "provider",
        confidence: "reported",
        input_tokens: 2,
        output_tokens: 1,
        cost_micros: 3,
        currency: "USD"
      }

      for _ <- 1..2,
          do:
            assert(
              {:ok, _} =
                Cuckoding.Telemetry.Accounting.record_usage(session.id, "usage-#{index}", usage)
            )
    end

    stats = BoardControl.Statistics.snapshot(BoardControl.get(batch.id))
    assert length(stats.sessions) == 106
    assert stats.tokens.input_tokens.value == 210
    assert stats.tokens.input_tokens.covered == 105
    assert stats.tokens.input_tokens.partial?
    assert stats.tokens.cache_read_tokens.value == nil
    assert [%{measure: %{value: 315}, source: "provider_reported"}] = stats.costs
    refute stats.resources.available?
  end

  test "failed preparation without an environment can be retried without losing history", %{
    board: board
  } do
    task(board.id, "Recover preparation", 1)
    batch = start(board.id)
    {:ok, _} = Workflows.transition_task(batch.controller_task_id, "ready", "ready-controller")

    {:ok, run} =
      Cuckoding.Execution.create_run(%{
        task_id: batch.controller_task_id,
        sequence: 1,
        board_execution_id: batch.id,
        policy_snapshot_id: batch.snapshot_json["policy_id"],
        base_sha: batch.base_sha,
        branch: "cuckoding/failed-preparation"
      })

    assert {:ok, _} = Cuckoding.Execution.fail_run_preparation(run.id, :fixture_failure)
    dispatch()
    blocked = BoardControl.get(batch.id)
    assert blocked.state == "attention"
    assert {:ok, retried} = BoardControl.control(batch.id, blocked.revision, "retry", "retry")
    assert retried.current_run_id == nil
    assert Repo.get!(Run, run.id).state == "failed"
    dispatch()
    assert BoardControl.get(batch.id).phase == "delivery"
    assert length(Cuckoding.Execution.list_runs(batch.controller_task_id)) == 2
  end

  test "owned controller cannot launch through the delivery entrypoint", %{board: board} do
    task = task(board.id, "Keep controller purpose", 1)
    batch = start(board.id)
    {:ok, _} = Workflows.transition_task(batch.controller_task_id, "ready", "ready-controller")

    {:ok, prepared} =
      ProjectWorkflow.prepare_task(batch.controller_task_id, board_execution_id: batch.id)

    assert {:error, :board_owned} = Cuckoding.GuidedRun.start(prepared.run.id, async: false)
    assert Repo.get!(Run, prepared.run.id).state == "queued"

    task |> Ecto.Changeset.change(description: "Edited after preparation") |> Repo.update!()

    assert {:error, :stale_task_snapshot} =
             BoardControl.Decision.start(prepared.run.id, async: false)

    assert Repo.get!(Run, prepared.run.id).state == "queued"

    refute Repo.exists?(
             from a in Cuckoding.Execution.StageAttempt, where: a.run_id == ^prepared.run.id
           )
  end

  test "protected changes halt before review or head advancement", %{
    board: board,
    project: project
  } do
    task = task(board.id, "Protected candidate", 1)
    policy = Cuckoding.Projects.latest_config_version(project.id)

    {:ok, _} =
      Cuckoding.Projects.add_config_version(%{
        project_id: project.id,
        revision: policy.revision + 1,
        source_hash: String.duplicate("b", 64),
        trusted_at: Cuckoding.Clock.wall_now(),
        config_json:
          Map.put(policy.config_json, "repository", %{
            "protected_paths" => ["WALKING_SKELETON.md"]
          })
      })

    batch = start(board.id)
    dispatch()
    dispatch()
    halted = BoardControl.get(batch.id)
    assert halted.state == "attention"
    assert halted.issue == "protected_path_approval_required"
    assert halted.head_sha == batch.base_sha
    assert [run] = Cuckoding.Execution.list_runs(task.id)
    assert run.state == "blocked"

    refute Repo.exists?(
             from(s in Cuckoding.Execution.AgentSession,
               join: a in Cuckoding.Execution.StageAttempt,
               on: a.id == s.stage_attempt_id,
               where: a.run_id == ^run.id and a.stage_key == "qa"
             )
           )
  end

  test "controller budget exhaustion keeps the batch closed", %{board: board} do
    task(board.id, "Budgeted batch", 1)
    batch = start(board.id)

    batch
    |> Ecto.Changeset.change(snapshot_json: Map.put(batch.snapshot_json, "maximum_decisions", 1))
    |> Repo.update!()

    for _ <- 1..4, do: dispatch()
    assert BoardControl.get(batch.id).issue == "controller_budget_exhausted"
    assert BoardControl.get(batch.id).state == "attention"
  end

  test "skipping a delivery retains its unreviewed commit without handing it to the next task", %{
    board: board
  } do
    first = task(board.id, "Unreviewed work", 9)
    second = task(board.id, "Clean handoff", 1)
    batch = start(board.id)
    dispatch()
    {:ok, _} = Workflows.transition_task(first.id, "ready", "skip-ready")
    {:ok, prepared} = ProjectWorkflow.prepare_task(first.id, board_execution_id: batch.id)
    {:ok, _} = Cuckoding.Execution.transition_run(prepared.run.id, "running", "skip-running")

    File.write!(
      Path.join(prepared.environment.worktree_path, "unfinished.md"),
      "Preserve this unreviewed work"
    )

    {:ok, candidate} =
      GitService.commit_candidate(
        prepared.environment,
        ["unfinished.md"],
        "test: unfinished candidate"
      )

    current = BoardControl.get(batch.id)

    assert {:ok, skipped} =
             BoardControl.control(batch.id, current.revision, "skip", "skip-active",
               confirmed: true
             )

    assert skipped.head_sha == batch.base_sha
    assert File.read!(Path.join(candidate.worktree_path, "unfinished.md")) =~ "Preserve"
    dispatch()
    dispatch()
    [run] = Cuckoding.Execution.list_runs(second.id)
    assert run.base_sha == batch.base_sha
    environment = Repo.get_by!(Environment, run_id: run.id)
    refute File.exists?(Path.join(environment.worktree_path, "unfinished.md"))
    assert Repo.get!(Run, prepared.run.id).state == "cancelled"
  end

  test "equal priority uses creation time then ID and concurrent starts acquire only one batch",
       %{board: board} do
    first = task(board.id, "Tie one", 2)
    second = task(board.id, "Tie two", 2)
    second |> Ecto.Changeset.change(inserted_at: first.inserted_at) |> Repo.update!()
    {:ok, preview} = BoardControl.preflight(board.id)

    results =
      for key <- ["competing-one", "competing-two"],
          do: Task.async(fn -> BoardControl.start(board.id, preview.digest, [], key, true) end)

    outcomes = Enum.map(results, &Task.await(&1, 10_000))
    assert Enum.count(outcomes, &match?({:ok, _}, &1)) == 1
    batch = BoardControl.current(board.id)
    assert {:ok, item} = BoardControl.next_item(batch)
    assert item.task_id == min(first.id, second.id)
  end

  test "board controls suspend an owned controller process and resume its validated decision", %{
    board: board
  } do
    task(board.id, "Pause the controller", 1)
    batch = start(board.id)
    {:ok, _} = Workflows.transition_task(batch.controller_task_id, "ready", "gated-ready")

    {:ok, prepared} =
      ProjectWorkflow.prepare_task(batch.controller_task_id, board_execution_id: batch.id)

    {:ok, _} =
      RunControl.admit(
        prepared.run.id,
        fn ->
          Cuckoding.Execution.transition_run(prepared.run.id, "running", "gated-running")
        end,
        board_controller: true
      )

    {:ok, skeleton} = WalkingSkeleton.load(prepared.run.id)
    gate = Path.join(skeleton.environment.run_dir, "release-gate")

    {:ok, handle} =
      Cuckoding.Execution.LocalProcessRunner.start(
        skeleton.environment,
        %{
          executable: "/bin/sh",
          args: ["-c", "while [ ! -f \"$1\" ]; do sleep 0.02; done", "controller-gate", gate]
        },
        timeout: 10_000,
        termination_grace_ms: 25
      )

    {:ok, input} = BoardControl.decision_input(BoardControl.get(batch.id))
    {:ok, runtime} = Cuckoding.AgentRuntime.resolve(skeleton, "spec_writer")
    runtime = %{runtime | options: [process: %{runner: GateResult, handle: handle}]}

    worker =
      Task.async(fn ->
        RunControl.track(skeleton.run.id, :workflow, fn ->
          with {:ok, output} <- WalkingSkeleton.control_stage(skeleton, runtime, input, []),
               do: BoardControl.accept_decision(skeleton.run.id, input, output)
        end)
      end)

    wait_for_controller(skeleton.run.id)
    current = BoardControl.get(batch.id)

    assert {:ok, paused} =
             BoardControl.control(batch.id, current.revision, "pause", "gated-pause")

    assert paused.state == "paused"
    assert {:error, :board_owned} = RunControl.control(skeleton.run.id, "resume")
    File.write!(gate, "continue")
    assert Task.yield(worker, 50) == nil
    assert {:ok, _} = BoardControl.control(batch.id, paused.revision, "resume", "gated-resume")
    assert {:ok, result} = Task.await(worker, 10_000)
    assert result.phase == "delivery"
    assert Cuckoding.Execution.LocalHostInspector.groups_empty?([handle.process.pgid])
    assert Repo.get!(Run, skeleton.run.id).state == "done"
  end

  defp wait_for_controller(run_id, remaining \\ 100)
  defp wait_for_controller(_run_id, 0), do: flunk("controller session did not start")

  defp wait_for_controller(run_id, remaining) do
    attempt = Repo.get_by(Cuckoding.Execution.StageAttempt, run_id: run_id)

    if attempt && Repo.get_by(Cuckoding.Execution.AgentSession, stage_attempt_id: attempt.id),
      do: :ok,
      else:
        (
          Process.sleep(10)
          wait_for_controller(run_id, remaining - 1)
        )
  end

  defp start(board) do
    {:ok, preview} = BoardControl.preflight(board)
    {:ok, batch} = BoardControl.start(board, preview.digest, [], "start", true)
    batch
  end

  defp task(board, title, priority) do
    {:ok, task} =
      ProjectWorkflow.create_task(board, %{"title" => title, "priority" => to_string(priority)})

    task
  end

  defp dispatch(options \\ []) do
    assert :ok =
             BoardControl.dispatch_once(
               Keyword.merge(options,
                 async: false,
                 resource_probe: %{
                   memory_available_bytes: fn -> {:ok, 32_000_000_000} end,
                   available_ports: fn _ -> {:ok, 100} end
                 }
               )
             )
  end

  defp git!(repo, args) do
    {output, 0} = System.cmd("/usr/bin/git", args, cd: repo, stderr_to_stdout: true)
    output
  end
end
