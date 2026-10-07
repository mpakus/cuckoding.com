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

  defmodule RecoveryFailure do
    defdelegate capabilities(options), to: Cuckoding.Adapters.FakeAdapter

    def start(_request, options) do
      File.write!(
        Path.join(options[:environment].worktree_path, "WALKING_SKELETON.md"),
        "Unfinished work retained for continuation\n"
      )

      Process.sleep(10)

      {:error, Keyword.fetch!(options, :failure)}
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

  test "preparation stops at reviewed Draft tasks until one idempotent Run", %{board: board} do
    assert {:ok, e} =
             BoardControl.prepare_goal(board.id, "Build a useful tested application", "prepare")

    snapshot = e.snapshot_json
    assert snapshot["completion_mode"] == "planning"

    assert {:ok, replay} =
             BoardControl.prepare_goal(board.id, "Build a useful tested application", "prepare")

    assert replay.id == e.id
    dispatch()
    dispatch()
    ready = BoardControl.get(e.id)
    assert ready.phase == "ready_to_run", inspect(ready.issue)
    assert ready.state == "waiting"
    assert ready.delivery_authorization_json == nil
    [item] = BoardControl.items(e.id)
    assert Workflows.get_task(item.task_id).state == "draft"
    for _ <- 1..3, do: dispatch()
    assert Cuckoding.Execution.list_runs(item.task_id) == []

    assert {:error, "delivery_not_authorized"} =
             BoardControl.control(e.id, ready.revision, "resume", "resume-unapproved")

    assert {:error, :task_not_ready} =
             ProjectWorkflow.prepare_task(item.task_id, board_execution_id: e.id)

    {:ok, _} = Workflows.transition_task(item.task_id, "ready", "attempt-bypass")

    assert {:error, :board_owned} =
             ProjectWorkflow.prepare_task(item.task_id, board_execution_id: e.id)

    assert {:ok, preview} = BoardControl.delivery_preview(e.id)
    assert preview.snapshot["goal"]["goal"] == "Build a useful tested application"
    assert {:ok, running} = BoardControl.activate_goal(e.id, preview.digest, "run")
    assert running.phase == "decision"
    assert running.delivery_authorization_json["digest"] == preview.digest
    assert running.snapshot_json == snapshot
    assert {:ok, replay} = BoardControl.activate_goal(e.id, preview.digest, "run")
    assert replay.id == e.id

    assert {:error, "goal_not_ready"} =
             BoardControl.activate_goal(e.id, preview.digest, "run-again")

    dispatch()
    dispatch()
    assert [%Run{state: "done"}] = Cuckoding.Execution.list_runs(item.task_id)
    dispatch()
    dispatch()
    assert %{phase: "final_review", state: "running"} = BoardControl.get(e.id)
    refute hd(BoardControl.Statistics.for_board(board.id).criteria)["passed"]
    dispatch()
    done = BoardControl.get(e.id)

    assert done.state == "done",
           inspect(Map.take(done, [:state, :phase, :issue, :current_run_id]))

    final = BoardControl.GoalReview.latest(e.id)
    assert final["passed"]
    assert final["head_sha"] == done.head_sha
    assert [%{"exit_status" => 0, "phase" => "check"}] = final["checks"]
    assert hd(BoardControl.Statistics.for_board(board.id).criteria)["passed"]

    [run] = Cuckoding.Execution.list_runs(item.task_id)
    env = Repo.get_by!(Environment, run_id: run.id)

    assert {:ok, %{"schema_version" => 2, "tests" => [], "goal_context" => context}} =
             WalkingSkeleton.validated_evidence(env)

    assert context["task_criteria"] == ["C1"]
    assert context["authorization_digest"] == preview.digest
  end

  test "goal commands reject unknown tools, inline programs, outside paths and incomplete declarations" do
    command = %{"name" => "test", "phase" => "check", "command" => ["git", "diff", "--check"]}
    assert {:ok, [resolved]} = BoardControl.GoalChecks.prepare([command])
    assert Path.type(hd(resolved["command"])) == :absolute

    for argv <- [
          ["sh", "-c", "true"],
          ["node", "-e", "true"],
          ["node", "--test", "../other.js"],
          ["node", "--test", "/private/other.js"],
          ["./node", "--test"],
          ["git", "push"],
          ["true"]
        ] do
      assert {:error, :invalid_goal_commands} =
               BoardControl.GoalChecks.prepare([%{command | "command" => argv}])
    end

    for declarations <- [
          [],
          [command, command],
          [%{command | "phase" => "setup"}],
          [%{"command" => ["git"]}]
        ] do
      assert {:error, :invalid_goal_commands} = BoardControl.GoalChecks.prepare(declarations)
    end
  end

  test "native tools are verified before Ready and frozen without importing the host environment",
       %{board: board} do
    native = fixture_node()
    {:ok, e} = BoardControl.prepare_goal(board.id, "Use the installed Node tool", "native-tools")
    dispatch(fake_decision: tool_plan(native))

    dispatch(
      fake_decision: fn input ->
        assert native in input["available_tools"]["node"]
        assert [%{"path" => ^native}] = input["toolchain"]["toolchain"]["tools"]
        BoardControl.Plans.fake_output(input)
      end
    )

    assert BoardControl.get(e.id).phase == "ready_to_run"
    {:ok, preview} = BoardControl.delivery_preview(e.id)
    assert [%{"path" => ^native, "name" => "node"}] = preview.snapshot["toolchain"]["tools"]
    {:ok, _} = BoardControl.activate_goal(e.id, preview.digest, "native-run")
    assert :ok = BoardControl.launch_authorized(%Run{board_execution_id: e.id})
    dispatch()
    selected = BoardControl.get(e.id)
    {:ok, _} = Workflows.transition_task(selected.current_task_id, "ready", "native-ready")

    {:ok, prepared} =
      ProjectWorkflow.prepare_task(selected.current_task_id, board_execution_id: e.id)

    {:ok, _} = Cuckoding.Execution.transition_run(prepared.run.id, "running", "native-running")
    {:ok, environment} = Cuckoding.Execution.LocalProcessRunner.prepare(prepared.environment, [])

    {:ok, result} =
      Cuckoding.Execution.LocalProcessRunner.exec(
        environment,
        %{executable: "/usr/bin/env", args: []}
      )

    assert result.output =~ "PATH=#{Path.dirname(native)}:/usr/bin:/bin:/usr/sbin:/sbin"
    assert result.output =~ "HOME=#{Path.join([environment.run_dir, "agent", "home"])}"
    refute result.output =~ "CUCKODING_RUNTIME_HOME"
    refute result.output =~ "must-not-be-inherited"

    File.write!(native, "#!/bin/sh\necho changed-tool\n")

    assert {:error, :goal_toolchain_changed} =
             RunControl.launch(prepared.run.id, fn -> send(self(), :changed_tool_launched) end)

    refute_received :changed_tool_launched
  end

  test "an unusable installed tool stops before Ready with its owned version log retained", %{
    board: board
  } do
    native = fixture_node("exit 42")
    {:ok, e} = BoardControl.prepare_goal(board.id, "Require this Node runtime", "bad-tool")
    dispatch(fake_decision: tool_plan(native))
    dispatch()
    current = BoardControl.get(e.id)
    assert current.state == "attention"
    assert current.issue == "goal_toolchain_unavailable"
    assert BoardControl.items(e.id) == []
    assert current.delivery_authorization_json == nil

    assert [%{exit_code: 42, ended_at: ended}] =
             Repo.all(
               from p in Cuckoding.Execution.ProcessRecord,
                 join: env in Environment,
                 on: env.id == p.environment_id,
                 where: env.run_id == ^current.current_run_id
             )

    assert ended
  end

  test "a failed required check overrides an optimistic final reviewer and repairs without Run again",
       %{board: board} do
    e =
      ready_for_final_review(board, [
        %{
          "name" => "test",
          "phase" => "check",
          "command" => ["node", "--test", "missing-goal.test.js"]
        }
      ])

    authorization = e.delivery_authorization_json
    dispatch()
    current = BoardControl.get(e.id)
    assert current.phase == "planning", inspect(current.issue)
    assert current.state == "running"
    assert current.plan_cycle == 1
    review = BoardControl.GoalReview.latest(e.id)
    refute review["passed"]
    assert [%{"exit_status" => status}] = review["checks"]
    assert status != 0
    assert [%{"verdict" => "pass"}] = review["criteria"]
    dispatch()
    dispatch()
    current = BoardControl.get(e.id)
    assert current.phase == "decision", inspect(current.issue)
    assert current.delivery_authorization_json == authorization
    assert Enum.any?(BoardControl.items(e.id), &(&1.state == "pending"))
    refute hd(BoardControl.Statistics.for_board(board.id).criteria)["passed"]
  end

  test "final checks replay once and reject forged or changed artifacts", %{board: board} do
    e = ready_for_final_review(board)
    dispatch()
    final = BoardControl.GoalReview.latest(e.id)
    assert final["passed"]
    e = BoardControl.get(e.id)
    run = Repo.get!(Run, final["run_id"])
    assert :ok = BoardControl.GoalChecks.verify(e, run, final["checks"])
    [check] = final["checks"]

    assert {:error, :invalid_goal_check_evidence} =
             BoardControl.GoalChecks.verify(e, run, [%{check | "exit_status" => 42}])

    assert {:error, :invalid_goal_check_evidence} =
             BoardControl.GoalChecks.verify(%{e | head_sha: e.base_sha}, run, final["checks"])

    env = Repo.get_by!(Environment, run_id: run.id)
    assert {:ok, skeleton} = WalkingSkeleton.load(run.id)
    assert {:ok, replay} = BoardControl.GoalChecks.run(skeleton, %{"phase" => "final_review"})
    assert replay["checks"] == final["checks"]

    File.write!(Path.join(env.worktree_path, "generated.txt"), "Check-generated work")

    assert {:ok, dirty_replay} =
             BoardControl.GoalChecks.run(skeleton, %{"phase" => "final_review"})

    refute dirty_replay["candidate_clean"]
    assert dirty_replay["checks"] == final["checks"]

    assert Repo.aggregate(
             from(event in Cuckoding.Execution.RunEvent,
               where: event.run_id == ^run.id and event.event_type == "goal.check_started"
             ),
             :count
           ) == 1

    File.write!(Path.join([env.run_dir, "artifacts", check["path"]]), "tampered")

    assert {:error, :invalid_goal_check_evidence} =
             BoardControl.GoalChecks.verify(e, run, final["checks"])
  end

  test "two reviewed tasks that regress integration repair automatically at the final head", %{
    board: board,
    project: project
  } do
    File.write!(Path.join(project.repo_path, "test_integration.py"), """
    import pathlib
    import unittest
    class Integration(unittest.TestCase):
        def test_both_requirements_survive(self):
            result = pathlib.Path('WALKING_SKELETON.md').read_text()
            self.assertIn('First', result)
            self.assertIn('Second', result)
    """)

    File.write!(Path.join(project.repo_path, ".gitignore"), "__pycache__/\n")
    git!(project.repo_path, ["add", "test_integration.py", ".gitignore"])
    git!(project.repo_path, ["commit", "-m", "Fixture integration contract"])

    {:ok, e} =
      BoardControl.prepare_goal(board.id, "Retain First and Second together", "integrate")

    dispatch(
      fake_decision: fn input ->
        BoardControl.Plans.fake_output(input)
        |> Map.put("changes", [
          Map.put(change("new_first", [], []), "title", "First"),
          Map.put(change("new_second", ["new_first"], []), "title", "Second")
        ])
        |> Map.put("commands", [
          %{
            "name" => "integration",
            "phase" => "check",
            "command" => ["python3", "-m", "unittest"]
          }
        ])
      end
    )

    dispatch()
    {:ok, preview} = BoardControl.delivery_preview(e.id)
    {:ok, _} = BoardControl.activate_goal(e.id, preview.digest, "one-integration-run")
    for _ <- 1..7, do: dispatch()
    assert %{phase: "final_review", state: "running"} = BoardControl.get(e.id)
    assert Enum.all?(BoardControl.items(e.id), &(&1.state == "done"))
    dispatch()
    failed = BoardControl.GoalReview.latest(e.id)
    refute failed["passed"]
    [failed_check] = failed["checks"]
    failed_environment = Repo.get_by!(Environment, run_id: failed["run_id"])

    assert failed_check["exit_status"] == 1,
           File.read!(Path.join([failed_environment.run_dir, "artifacts", failed_check["path"]]))

    assert BoardControl.get(e.id).phase == "planning"

    dispatch(
      fake_decision: fn input ->
        assert input["final_review"]["head_sha"] == failed["head_sha"]

        BoardControl.Plans.fake_output(input)
        |> put_in(["changes", Access.at(0), "title"], "First and Second")
      end
    )

    dispatch()
    for _ <- 1..5, do: dispatch()
    done = BoardControl.get(e.id)
    final = BoardControl.GoalReview.latest(e.id)
    assert done.state == "done", inspect(done.issue)
    assert final["passed"]
    assert final["head_sha"] == done.head_sha
    refute final["head_sha"] == failed["head_sha"]
    assert final["authorization_digest"] == preview.digest
    assert length(BoardControl.items(e.id)) == 3
    assert BoardControl.Plans.questions(e.id) == []
  end

  test "final review cannot omit criteria or claim another head", %{board: board} do
    e = ready_for_final_review(board)

    dispatch(
      fake_decision: fn input ->
        BoardControl.Plans.fake_output(input) |> Map.put("criteria", [])
      end
    )

    assert BoardControl.get(e.id).state == "attention"
    assert BoardControl.get(e.id).issue == "invalid_final_goal_review"
    assert BoardControl.GoalReview.latest(e.id) == nil
  end

  test "editing the brief requires another plan review and invalidates the old Run preview", %{
    board: board
  } do
    {:ok, e} = BoardControl.prepare_goal(board.id, "Original outcome", "prepare-edit")
    dispatch()
    dispatch()
    ready = BoardControl.get(e.id)
    {:ok, preview} = BoardControl.delivery_preview(e.id)

    assert {:ok, revised} =
             BoardControl.revise_brief(e.id, ready.revision, "Revised outcome", "edit")

    assert revised.phase == "planning"
    assert revised.preparation_json == %{"brief" => "Revised outcome", "revision" => 2}
    assert revised.snapshot_json == ready.snapshot_json

    assert {:error, "goal_not_ready"} =
             BoardControl.activate_goal(e.id, preview.digest, "stale-run")

    assert {:error, "brief_revision_not_permitted"} =
             BoardControl.revise_brief(e.id, ready.revision, "Stale edit", "stale-edit")

    dispatch()
    dispatch()
    assert BoardControl.get(e.id).phase == "ready_to_run"
    {:ok, next} = BoardControl.delivery_preview(e.id)
    refute next.digest == preview.digest
    assert next.snapshot["goal"]["goal"] == "Revised outcome"

    assert {:error, "stale_preflight_or_workspace_paused"} =
             BoardControl.activate_goal(e.id, preview.digest, "stale-ready-run")

    assert {:ok, _} = BoardControl.activate_goal(e.id, next.digest, "revised-run")
  end

  test "controller schemas bind the current envelope instead of nested proposal identity" do
    for phase <- ~w(planning plan_review decision final_review) do
      input = %{
        "phase" => phase,
        "preparing" => true,
        "prepared_goal" => true,
        "execution_id" => "current-goal",
        "revision" => 8,
        "head_sha" => "reviewed-head",
        "plan" => %{"id" => "current-plan", "proposal" => %{"revision" => 2}}
      }

      properties = BoardControl.Plans.schema(input)["properties"]
      assert properties["execution_id"]["enum"] == ["current-goal"]
      assert properties["revision"]["enum"] == [8]
      if phase == "plan_review", do: assert(properties["plan_id"]["enum"] == ["current-plan"])
      if phase == "final_review", do: assert(properties["head_sha"]["enum"] == ["reviewed-head"])
      assert BoardControl.Plans.objective(input) =~ "TOP-LEVEL execution_id and revision"
    end
  end

  test "host-invalid goal plans receive bounded correction without importing tasks", %{
    board: board
  } do
    {:ok, e} = BoardControl.prepare_goal(board.id, "Cover every requirement", "correct-invalid")

    dispatch(
      fake_decision: fn input ->
        BoardControl.Plans.fake_output(input)
        |> Map.put("criteria", [%{"id" => "C2", "text" => "Unmapped requirement"}])
      end
    )

    assert BoardControl.get(e.id).phase == "planning"
    assert BoardControl.items(e.id) == []

    assert [%{state: "rejected", review_run_id: nil} = rejected] =
             BoardControl.Plans.revisions(e.id)

    assert rejected.review_json["source"] == "host_validation"

    dispatch()
    assert BoardControl.get(e.id).phase == "plan_review"
    assert BoardControl.items(e.id) == []
    dispatch()
    assert BoardControl.get(e.id).phase == "ready_to_run"
    assert BoardControl.Plans.accepted(e).review_run_id != nil
  end

  test "repeated host-invalid plans consume the existing three-proposal ceiling", %{board: board} do
    {:ok, e} = BoardControl.prepare_goal(board.id, "Cover every requirement", "invalid-ceiling")

    for _ <- 1..3 do
      dispatch(
        fake_decision: fn input ->
          BoardControl.Plans.fake_output(input) |> Map.put("changes", [])
        end
      )
    end

    assert %{state: "attention", issue: "plan_review_limit"} = BoardControl.get(e.id)
    assert length(BoardControl.Plans.revisions(e.id)) == 3
    assert BoardControl.items(e.id) == []
    dispatch()
    assert length(BoardControl.Plans.revisions(e.id)) == 3
  end

  test "malformed generated criteria fail closed and preparation can be discarded", %{
    board: board
  } do
    {:ok, e} = BoardControl.prepare_goal(board.id, "Whole brief", "malformed-plan")
    {:ok, input} = BoardControl.decision_input(e)
    output = BoardControl.Plans.fake_output(input)

    command_name =
      BoardControl.Plans.schema(input)["properties"]["commands"]["items"]["properties"]["name"]

    assert command_name["maxLength"] == 40
    pattern = Regex.compile!(command_name["pattern"])
    assert Regex.match?(pattern, "node_tests")
    refute Regex.match?(pattern, "Run Node built-in test suite")
    assert BoardControl.Plans.objective(input) =~ "lowercase snake_case"

    for criteria <- [
          [nil],
          [%{"id" => "C1", "text" => ""}],
          [%{"id" => "C1", "text" => "Pass", "grant" => "write"}]
        ] do
      assert {:error, :invalid_goal_plan} =
               BoardControl.Plans.validate(e, Map.put(output, "criteria", criteria))
    end

    dispatch()
    dispatch()
    ready = BoardControl.get(e.id)

    assert {:ok, stopped} =
             BoardControl.control(e.id, ready.revision, "stop", "discard", confirmed: true)

    assert stopped.state == "stopped"
    assert BoardControl.current(board.id) == nil
    assert BoardControl.items(e.id) != []
    assert BoardControl.Plans.revisions(e.id) != []
  end

  test "project brief creates its board once and reconnects to one reviewed Run action", %{
    conn: conn,
    project: project
  } do
    policy = Cuckoding.Projects.latest_config_version(project.id)

    roles =
      Enum.map(
        Cuckoding.ProjectOnboarding.default_roles(),
        &Map.put(&1, "agent_connection_key", "fixture")
      )

    config =
      Map.merge(policy.config_json, %{
        "default_roles" => roles,
        "agent_connections" => [
          %{"key" => "fixture", "label" => "Fixture", "adapter_key" => "fake", "settings" => %{}}
        ]
      })

    {:ok, _} =
      Cuckoding.Projects.add_config_version(%{
        project_id: project.id,
        revision: policy.revision + 1,
        config_json: config,
        source_hash: "fixture-team",
        trusted_at: Cuckoding.Clock.wall_now()
      })

    {:ok, view, _} = live(conn, ~p"/projects/#{project.id}")
    assert Cuckoding.ProjectDelivery.board(project.id) == nil

    view
    |> form("#project-goal-form", goal: %{brief: "Build the described application"})
    |> render_change()

    send(view.pid, {:activity_event, "fixture", 1})
    assert render(view) =~ "Build the described application"
    view |> form("#project-goal-form") |> render_submit()
    render_async(view, 10_000)
    board = Cuckoding.ProjectDelivery.board(project.id)
    assert board
    e = BoardControl.current(board.id)
    assert e && e.phase == "planning", render(view)

    assert {:ok, replay} =
             Cuckoding.ProjectDelivery.prepare(
               project.id,
               "Build the described application",
               "reconnect"
             )

    assert replay.id == e.id
    dispatch()
    dispatch()
    {:ok, reconnected, _} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(reconnected, "#goal-state", "Ready to run"),
           inspect(BoardControl.get(e.id))

    assert has_element?(reconnected, "#run-goal", "Run")
    refute has_element?(reconnected, "input[type=checkbox]")
    reconnected |> element("#stop-goal") |> render_click()

    assert has_element?(
             reconnected,
             "#stop-goal-modal[data-cancel='cancel-stop'][data-return-focus='stop-goal']"
           )

    reconnected |> element("#stop-goal-modal button[phx-click='cancel-stop']") |> render_click()
    refute has_element?(reconnected, "#stop-goal-modal")
    assert BoardControl.get(e.id).state == "waiting"
    reconnected |> element("#run-goal") |> render_click()
    render_async(reconnected, 10_000)
    assert BoardControl.get(e.id).delivery_authorization_json
    refute has_element?(reconnected, "#run-goal")
    assert Cuckoding.ProjectDelivery.board(project.id).id == board.id
    for _ <- 1..6, do: dispatch()
    send(reconnected.pid, :tick)
    assert has_element?(reconnected, "#goal-state", "Done"), render(reconnected)
    assert has_element?(reconnected, "#goal-progress", "Reviewer")
    assert has_element?(reconnected, "#goal-result", "Final goal verification")
    assert has_element?(reconnected, "#goal-result", "Local branch:")
    assert has_element?(reconnected, "#goal-result", "integrity: passed")
    assert has_element?(reconnected, "#goal-open-finder", "Open in Finder")
  end

  test "the goal deadline includes planning and closes every later process launch", %{
    board: board
  } do
    {:ok, e} = BoardControl.prepare_goal(board.id, "A bounded outcome", "bounded-goal")
    dispatch()
    dispatch()
    {:ok, preview} = BoardControl.delivery_preview(e.id)
    {:ok, _} = BoardControl.activate_goal(e.id, preview.digest, "bounded-run")
    dispatch()
    selected = BoardControl.get(e.id)
    {:ok, _} = Workflows.transition_task(selected.current_task_id, "ready", "expiring-task-ready")

    {:ok, prepared} =
      ProjectWorkflow.prepare_task(selected.current_task_id, board_execution_id: e.id)

    {:ok, _} = Cuckoding.Execution.transition_run(prepared.run.id, "running", "test-expiring-run")

    expired =
      Repo.update!(
        Ecto.Changeset.change(BoardControl.get(e.id),
          inserted_at: DateTime.add(Cuckoding.Clock.wall_now(), -121 * 60, :second)
        )
      )

    assert {:error, :goal_budget_exhausted} = BoardControl.Budget.check(expired)

    assert {:error, :goal_budget_exhausted} =
             RunControl.launch(prepared.run.id, fn -> send(self(), :unauthorized_launch) end)

    refute_received :unauthorized_launch
    dispatch()
    assert BoardControl.get(e.id).state == "attention"
    assert BoardControl.get(e.id).issue == "goal_budget_exhausted"

    assert BoardControl.get(e.id).delivery_authorization_json ==
             expired.delivery_authorization_json

    assert {:ok, replay} =
             BoardControl.prepare_goal(board.id, "A bounded outcome", "bounded-goal")

    assert replay.id == e.id
    assert {:error, :goal_budget_exhausted} = BoardControl.Budget.check(replay)
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

  test "autonomous empty board plans with the saved independent Reviewer and delivers", %{
    board: board
  } do
    goal = %{"goal" => "Implement the approved goal", "criteria" => "A reviewed change exists"}
    assert {:ok, preview} = BoardControl.preflight(board.id, [], goal)

    assert {:ok, batch} =
             BoardControl.start(board.id, preview.digest, [], "goal-start", true, goal)

    assert batch.phase == "planning"
    dispatch()
    assert BoardControl.get(batch.id).phase == "plan_review"
    assert [proposal] = Cuckoding.BoardControl.Plans.revisions(batch.id)
    assert proposal.state == "proposed"
    dispatch()
    assert BoardControl.get(batch.id).phase == "decision", inspect(BoardControl.get(batch.id))

    assert [%{state: "accepted", review_run_id: review_id}] =
             Cuckoding.BoardControl.Plans.revisions(batch.id)

    review_run = Repo.get!(Run, review_id)
    assert Cuckoding.BoardControl.Decision.role(review_run) == "reviewer"
    assert [item] = BoardControl.items(batch.id)
    assert item.criteria_json == %{"ids" => ["C1"]}
    for _ <- 1..4, do: dispatch()
    assert BoardControl.get(batch.id).state == "done", inspect(BoardControl.get(batch.id))
  end

  test "task blocker defers descendants, independent work finishes, and explicit retry restores the queue",
       %{board: board} do
    a = task(board.id, "A", 9)
    b = task(board.id, "B depends on A", 8)
    c = task(board.id, "C independent", 1)
    {:ok, _} = Workflows.add_dependency(b.id, a.id)
    e = autonomous(board.id)
    dispatch()
    dispatch()
    dispatch(fake_decision: decision("block", a.id))
    assert Enum.find(BoardControl.items(e.id), &(&1.task_id == b.id)).state == "deferred"
    for _ <- 1..4, do: dispatch()
    current = BoardControl.get(e.id)
    assert current.state == "attention"
    assert current.issue == "remaining_tasks_blocked"
    assert Enum.find(BoardControl.items(e.id), &(&1.task_id == c.id)).state == "done"

    assert {:ok, _} =
             BoardControl.control(e.id, current.revision, "retry", "retry-a", task_id: a.id)

    for _ <- 1..8, do: dispatch()

    assert BoardControl.get(e.id).state == "done",
           inspect(
             Map.take(BoardControl.get(e.id), [
               :state,
               :issue,
               :phase,
               :current_task_id,
               :current_run_id
             ])
           )

    assert Enum.find(BoardControl.items(e.id), &(&1.task_id == a.id)).retry_count == 1
  end

  test "reviewed split preserves history and rejects cycles, foreign criteria and lifetime overflow",
       %{board: board} do
    original = task(board.id, "Original", 1)
    e = autonomous(board.id, %{"tasks" => "3"})
    dispatch()
    dispatch()
    dispatch(fake_decision: decision("replan", nil))

    proposed = fn input ->
      Map.merge(Map.take(input, ~w(execution_id revision)), %{
        "summary" => "Split within C1",
        "changes" => [
          change("new_first", [], [original.id]),
          change("new_second", ["new_first"], [original.id])
        ]
      })
    end

    current = BoardControl.get(e.id)
    {:ok, input} = BoardControl.decision_input(current)
    plan = proposed.(input)
    assert :ok = Cuckoding.BoardControl.Plans.validate(current, plan)

    assert {:error, :invalid_goal_plan} =
             Cuckoding.BoardControl.Plans.validate(
               current,
               put_in(plan, ["changes", Access.at(0), "dependencies"], ["new_second"])
             )

    assert {:error, :invalid_goal_plan} =
             Cuckoding.BoardControl.Plans.validate(
               current,
               put_in(plan, ["changes", Access.at(0), "criteria"], ["C99"])
             )

    assert {:error, :invalid_goal_plan} =
             Cuckoding.BoardControl.Plans.validate(
               current,
               Map.update!(plan, "changes", &(&1 ++ [change("new_extra", [], [])]))
             )

    dispatch(fake_decision: proposed)
    dispatch()
    members = BoardControl.items(e.id)
    assert length(members) == 3
    old = Enum.find(members, &(&1.task_id == original.id))
    assert old.superseded and old.state == "deferred"
    assert length(old.replacement_ids_json["ids"]) == 2
    assert Workflows.get_task(original.id).state == "cancelled"
    stats = Cuckoding.BoardControl.Statistics.snapshot(BoardControl.get(e.id))
    assert stats.totals["superseded"] == 1
    refute Map.has_key?(stats.totals, "done")
    for _ <- 1..8, do: dispatch()

    assert BoardControl.get(e.id).state == "done",
           inspect(
             Map.take(BoardControl.get(e.id), [
               :state,
               :issue,
               :phase,
               :current_task_id,
               :current_run_id
             ])
           )
  end

  test "concurrent edits invalidate a pending plan without importing it", %{board: board} do
    original = task(board.id, "Original", 1)
    e = autonomous(board.id)
    dispatch()
    {:ok, _} = Workflows.update_task(original.id, %{title: "Human edit"})
    dispatch()
    assert BoardControl.get(e.id).state == "attention"
    assert [%{state: "invalidated"}] = Cuckoding.BoardControl.Plans.revisions(e.id)
    assert Workflows.get_task(original.id).title == "Human edit"
    assert length(BoardControl.items(e.id)) == 1
  end

  test "durable clarification is idempotent, revision checked and cannot expand authorization", %{
    board: board
  } do
    e = autonomous(board.id)
    dispatch()
    dispatch()
    dispatch(fake_decision: decision("ask", nil))
    current = BoardControl.get(e.id)
    assert current.state == "attention"
    assert [question] = Cuckoding.BoardControl.Plans.questions(e.id)

    assert {:error, _} =
             BoardControl.control(e.id, current.revision, "resume", "resume-unanswered")

    current = BoardControl.get(e.id)
    assert {:error, _} = BoardControl.answer_question(e.id, 1, question.id, "Yes", "stale-answer")

    assert {:ok, answered} =
             BoardControl.answer_question(
               e.id,
               current.revision,
               question.id,
               "Use the existing scope",
               "answer"
             )

    assert {:ok, replay} =
             BoardControl.answer_question(
               e.id,
               current.revision,
               question.id,
               "Change permissions",
               "answer"
             )

    assert replay.id == answered.id
    assert answered.snapshot_json == e.snapshot_json
    assert [%{answer: "Use the existing scope"}] = Cuckoding.BoardControl.Plans.questions(e.id)
  end

  test "transient retry preserves the failed attempt, consumes its ceiling and keeps the reviewed base",
       %{board: board} do
    e = autonomous(board.id, %{"retries" => "1"})
    dispatch()
    dispatch()
    dispatch()
    current = BoardControl.get(e.id)
    {:ok, _} = Workflows.transition_task(current.current_task_id, "ready", "fixture-ready")

    {:ok, prepared} =
      ProjectWorkflow.prepare_task(current.current_task_id, board_execution_id: e.id)

    {:ok, _} = Cuckoding.Execution.transition_run(prepared.run.id, "running", "fixture-running")
    env = Repo.get_by!(Environment, run_id: prepared.run.id)
    File.write!(Path.join(env.worktree_path, "unfinished.txt"), "Retain this evidence")
    Cuckoding.OrchestrationFailure.fail(prepared.run.id, :workflow, :agent_timeout)
    dispatch()
    assert Enum.at(BoardControl.items(e.id), 0).retry_count == 1
    assert BoardControl.get(e.id).head_sha == e.base_sha
    assert Repo.get!(Run, prepared.run.id).state == "cancelled"
    dispatch()
    dispatch()
    dispatch()

    assert BoardControl.get(e.id).state == "done",
           inspect(
             Map.take(BoardControl.get(e.id), [
               :state,
               :issue,
               :phase,
               :current_task_id,
               :current_run_id
             ])
           )

    assert [new, old] = Cuckoding.Execution.list_runs(current.current_task_id)
    assert old.id == prepared.run.id
    new_env = Repo.get_by!(Environment, run_id: new.id)
    refute File.exists?(Path.join(new_env.worktree_path, "unfinished.txt"))
    assert File.exists?(Path.join(env.worktree_path, "unfinished.txt"))
    assert Cuckoding.OrchestrationFailure.recovery_class(:acp_permission_required) == "global"
    assert Cuckoding.OrchestrationFailure.recovery_class(:acp_process_failed) == "global"
  end

  test "planning pauses and stops without importing or replaying work", %{board: board} do
    e = autonomous(board.id)
    assert {:ok, paused} = BoardControl.control(e.id, e.revision, "pause", "pause-plan")
    dispatch()
    assert Cuckoding.BoardControl.Plans.revisions(e.id) == []
    assert {:ok, _} = BoardControl.control(e.id, paused.revision, "resume", "resume-plan")
    dispatch()
    current = BoardControl.get(e.id)
    assert current.phase == "plan_review"

    assert {:ok, _} =
             BoardControl.control(e.id, current.revision, "stop", "stop-plan", confirmed: true)

    dispatch()
    assert BoardControl.items(e.id) == []
    assert [%{state: "proposed"}] = Cuckoding.BoardControl.Plans.revisions(e.id)
  end

  test "autonomous modal retains goal input and shows limits and separate consent", %{
    board: board,
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/boards/#{board.id}")
    view |> element("#start-board-button") |> render_click()
    view |> form("#start-board-form", batch: %{mode: "autonomous_goal"}) |> render_change()

    html =
      view
      |> form("#start-board-form",
        batch: %{
          mode: "autonomous_goal",
          goal: %{
            goal: "Approved goal",
            criteria: "Tests pass",
            tasks: "20",
            revisions: "3",
            retries: "2"
          }
        }
      )
      |> render_change()

    assert html =~ "Approved goal"
    assert html =~ "Lifetime tasks"
    assert html =~ "reviewed task import"
    send(view.pid, :board_tick)
    assert render(view) =~ "Approved goal"
  end

  test "same-model plan review is separate and controller continuation uses only saved evidence",
       %{board: board} do
    e = autonomous(board.id)
    dispatch()
    dispatch()
    dispatch()
    stats = Cuckoding.BoardControl.Statistics.snapshot(BoardControl.get(e.id))
    [planner, reviewer, controller] = stats.sessions
    assert planner.adapter_key == reviewer.adapter_key
    assert planner.requested_model == reviewer.requested_model
    refute planner.conversation_key == reviewer.conversation_key
    assert planner.conversation_key == controller.conversation_key
    assert controller.continuation_of_id == planner.id
    assert controller.continuation_mode == "saved_evidence"
    assert reviewer.effective_grant_json["requested"]["approval_mode"] == "plan"
    assert stats.tokens.input_tokens.value == nil
  end

  test "native continuation identity never crosses account, role, model, grant or workspace", %{
    board: board
  } do
    e = autonomous(board.id)
    dispatch()
    [session] = Cuckoding.BoardControl.Statistics.snapshot(BoardControl.get(e.id)).sessions

    identity =
      Map.merge(session.continuation_identity_json, %{"account" => "account", "model" => "model"})

    previous = %{session | continuation_identity_json: identity, actual_model: "model"}
    assert Cuckoding.BoardControl.Conversations.compatible?(previous, identity)

    for key <- ~w(account model role workspace grant adapter runtime_version) do
      refute Cuckoding.BoardControl.Conversations.compatible?(
               previous,
               Map.put(identity, key, "different")
             )
    end

    refute Cuckoding.BoardControl.Conversations.compatible?(
             %{previous | state: "failed"},
             identity
           )

    timed = put_in(identity, ["grant", "resource_limits", "wall_ms"], 20_000)
    previous = %{previous | continuation_identity_json: timed}

    assert Cuckoding.BoardControl.Conversations.compatible?(
             previous,
             put_in(timed, ["grant", "resource_limits", "wall_ms"], 10_000)
           )

    refute Cuckoding.BoardControl.Conversations.compatible?(
             previous,
             put_in(timed, ["grant", "resource_limits", "wall_ms"], 30_000)
           )
  end

  test "productive continuation retains the run and worktree and resumes through final review", %{
    board: board
  } do
    {e, skeleton} = recovery_run(board)
    assert {:recovering, recovery} = fail_delivery(skeleton, {:acp_turn_stopped, "max_tokens"})
    assert recovery["kind"] == "continuation"
    assert recovery["count"] == 1
    attempt = BoardControl.Recovery.pending(skeleton.run)
    assert attempt.wall_ms >= 10
    assert attempt.active_ms <= attempt.wall_ms

    assert File.read!(Path.join(skeleton.environment.worktree_path, "WALKING_SKELETON.md")) =~
             "Unfinished"

    assert Repo.get!(Run, skeleton.run.id).wait_reason == "goal_recovery"
    assert BoardControl.Recovery.ready?(Repo.get!(Run, skeleton.run.id))
    assert BoardControl.get(e.id).head_sha == e.base_sha

    dispatch()
    assert Repo.get!(Run, skeleton.run.id).state == "done"
    assert Repo.get_by!(Environment, run_id: skeleton.run.id).id == skeleton.environment.id

    assert Repo.aggregate(
             from(a in Cuckoding.Execution.StageAttempt,
               where: a.run_id == ^skeleton.run.id and a.stage_key == "specification"
             ),
             :count
           ) == 1

    assert {:error, :recovery_not_ready_or_owned} =
             RunControl.admit(skeleton.run.id, fn -> BoardControl.Recovery.claim(skeleton.run) end)

    for _ <- 1..4, do: dispatch()
    assert BoardControl.get(e.id).state == "done", inspect(BoardControl.get(e.id).issue)
    assert length(Cuckoding.Execution.list_runs(skeleton.task.id)) == 1
    assert [%{"kind" => "continuation"}] = BoardControl.Recovery.events(e)
  end

  test "an invalid goal decision corrects automatically before any task starts", %{board: board} do
    e = authorized_goal(board)
    authorization = e.delivery_authorization_json
    {:ok, input} = BoardControl.decision_input(e)
    schema = BoardControl.Plans.schema(input)
    assert schema["properties"]["task_id"]["enum"] == [nil, input["next_task_id"]]

    dispatch(
      fake_decision: fn current ->
        BoardControl.Decision.fake_output(current) |> Map.put("task_id", "wrong-task")
      end
    )

    waiting = BoardControl.get(e.id)
    run = Repo.get!(Run, waiting.current_run_id)
    assert run.state == "waiting" and run.wait_reason == "goal_recovery"
    assert waiting.current_task_id == nil
    assert [%{"code" => "invalid_goal_decision", "count" => 1}] = BoardControl.Recovery.events(e)
    make_recovery_due(run)

    dispatch(
      fake_decision: fn current ->
        assert current["recovery"]["code"] == "invalid_goal_decision"
        BoardControl.Decision.fake_output(current)
      end
    )

    selected = BoardControl.get(e.id)
    assert selected.phase == "delivery"
    assert selected.current_task_id == input["next_task_id"]
    assert selected.delivery_authorization_json == authorization
    assert Repo.get!(Run, run.id).state == "done"
    assert BoardControl.Plans.questions(e.id) == []
  end

  test "repeated invalid goal decisions exhaust the saved retry allowance", %{board: board} do
    e = authorized_goal(board)
    limit = e.snapshot_json["execution_profile"]["retries"]

    for attempt <- 1..(limit + 1) do
      dispatch(
        fake_decision: fn current ->
          BoardControl.Decision.fake_output(current) |> Map.put("task_id", "wrong-task")
        end
      )

      if attempt <= limit do
        current = BoardControl.get(e.id)
        make_recovery_due(Repo.get!(Run, current.current_run_id))
      end
    end

    dispatch()
    assert BoardControl.get(e.id).state == "attention"
    assert length(BoardControl.Recovery.events(e)) == limit
    assert Enum.all?(BoardControl.items(e.id), &(&1.state == "pending"))
  end

  test "provider backoff is durable, respects Pause and resumes without resetting other counters",
       %{board: board, project: project, conn: conn} do
    {e, skeleton} = recovery_run(board)
    assert {:recovering, recovery} = fail_delivery(skeleton, :provider_rate_limited)
    assert recovery["kind"] == "provider_wait"
    refute BoardControl.Recovery.ready?(Repo.get!(Run, skeleton.run.id))
    dispatch()
    assert Repo.get!(Run, skeleton.run.id).state == "waiting"
    assert length(BoardControl.Recovery.events(e)) == 1
    # Link this fixture's existing board as the project's delivery board.
    {:ok, _} =
      Cuckoding.Execution.Commands.execute_once(
        %{
          idempotency_key: "project:#{project.id}:delivery-board",
          kind: "project.delivery_board",
          target_type: "project",
          target_id: project.id
        },
        fn _ -> {:ok, %{"board_id" => board.id}} end
      )

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")
    assert html =~ "goal-recovery"
    assert has_element?(view, "#goal-recovery", "Waiting for the provider")
    assert has_element?(view, "#goal-recovery[role=status]")
    assert has_element?(view, "button[phx-value-action=pause]")
    current = BoardControl.get(e.id)
    assert {:ok, paused} = BoardControl.control(e.id, current.revision, "pause", "pause-wait")
    make_recovery_due(skeleton.run)
    dispatch()
    refute Repo.get!(Run, skeleton.run.id).state == "done"
    assert {:ok, _} = BoardControl.control(e.id, paused.revision, "resume", "resume-wait")
    dispatch()
    assert Repo.get!(Run, skeleton.run.id).state == "done", inspect(BoardControl.get(e.id).issue)
    assert Enum.at(BoardControl.items(e.id), 0).retry_count == 0
    assert [%{"kind" => "provider_wait", "count" => 1}] = BoardControl.Recovery.events(e)
  end

  test "continuations and failures consume separate finite counters without rerunning completed stages",
       %{board: board} do
    {e, skeleton} = recovery_run(board)

    assert {:recovering, %{"kind" => "transient", "count" => 1}} =
             fail_delivery(skeleton, :agent_timeout)

    for count <- 1..3 do
      claim_recovery(skeleton.run)

      assert {:recovering, data} =
               fail_delivery(skeleton, {:acp_turn_stopped, "max_turn_requests"}, resume: true)

      assert data["count"] == count
      assert data["kind"] == "continuation"
    end

    claim_recovery(skeleton.run)

    assert {:error, :goal_recovery_limit} =
             fail_delivery(skeleton, {:acp_turn_stopped, "max_turn_requests"}, resume: true)

    assert Enum.at(BoardControl.items(e.id), 0).retry_count == 1
    assert length(BoardControl.Recovery.events(e)) == 4
    assert Repo.get!(Run, skeleton.run.id).state == "blocked"

    assert Repo.aggregate(
             from(a in Cuckoding.Execution.StageAttempt,
               where: a.run_id == ^skeleton.run.id and a.stage_key == "specification"
             ),
             :count
           ) == 1

    dispatch()
    assert BoardControl.get(e.id).phase == "decision"
    dispatch()
    current = BoardControl.get(e.id)
    assert current.phase == "planning", inspect(current.issue)
    assert current.plan_cycle == 1
    assert BoardControl.Plans.repairable_tasks(current) == [skeleton.task.id]
    {:ok, input} = BoardControl.decision_input(current)
    failed = Enum.find(input["previous_outcomes"], &(&1["run_id"] == skeleton.run.id))
    assert failed["failure"]["code"] == "goal_recovery_limit"
    assert failed["failure"]["recovery_class"] == "task"
    proposed = repaired_plan(input, skeleton.task.id)
    assert :ok = BoardControl.Plans.validate(current, proposed)

    assert {:error, :invalid_goal_plan} =
             BoardControl.Plans.validate(
               current,
               put_in(
                 proposed,
                 ["changes", Access.at(0), "description"],
                 skeleton.task.description
               )
             )

    assert {:error, :invalid_goal_plan} =
             BoardControl.Plans.validate(
               current,
               put_in(proposed, ["changes", Access.at(0), "criteria"], ["C99"])
             )

    dispatch(fake_decision: &repaired_plan(&1, skeleton.task.id))
    assert Workflows.get_task(skeleton.task.id).state == "cancelled"
    assert length(Cuckoding.Execution.list_runs(skeleton.task.id)) == 1
    dispatch()
    assert Workflows.get_task(skeleton.task.id).state == "ready"
    assert Enum.at(BoardControl.items(e.id), 0).retry_count == 1
    for _ <- 1..5, do: dispatch()
    assert BoardControl.get(e.id).state == "done", inspect(BoardControl.get(e.id).issue)
    assert Enum.at(BoardControl.items(e.id), 0).retry_count == 1
    assert length(BoardControl.Recovery.events(e)) == 4
    assert length(Cuckoding.Execution.list_runs(skeleton.task.id)) == 2
    assert Repo.get!(Run, skeleton.run.id).state == "cancelled"

    assert File.read!(Path.join(skeleton.environment.worktree_path, "WALKING_SKELETON.md")) =~
             "Unfinished"
  end

  test "permission failures never enter automatic task repair", %{board: board} do
    {e, skeleton} = recovery_run(board)
    assert {:error, :acp_permission_required} = fail_delivery(skeleton, :acp_permission_required)
    dispatch()
    current = BoardControl.get(e.id)
    assert current.state == "attention"
    assert current.issue == "execution_failure_requires_attention"
    assert current.plan_cycle == 0
    assert BoardControl.Plans.repairable_tasks(current) == []
    refute Workflows.get_task(skeleton.task.id).state == "ready"
  end

  test "automatic changes of approach stop at the original revision ceiling", %{board: board} do
    {e, skeleton} = recovery_run(board)
    assert {:error, :goal_recovery_limit} = fail_delivery(skeleton, :goal_recovery_limit)
    dispatch()
    current = BoardControl.get(e.id)
    Repo.update!(Ecto.Changeset.change(current, plan_cycle: 3))
    before = Repo.aggregate(from(r in Run, where: r.board_execution_id == ^e.id), :count)
    dispatch()
    stopped = BoardControl.get(e.id)
    assert stopped.state == "attention"
    assert stopped.issue == "plan_revision_limit"
    assert stopped.plan_cycle == 3
    assert stopped.delivery_authorization_json == e.delivery_authorization_json
    assert Repo.aggregate(from(r in Run, where: r.board_execution_id == ^e.id), :count) == before
  end

  test "prepared questions require criterion-linked justification and are answered on the project",
       %{board: board, project: project, conn: conn} do
    e = authorized_goal(board)
    {:ok, input} = BoardControl.decision_input(e)

    output =
      Map.merge(BoardControl.Decision.fake_output(input), %{
        "action" => "ask",
        "task_id" => nil,
        "summary" => "Should the required export use CSV or JSON?",
        "question" => %{
          "kind" => "requirement_choice",
          "criterion_id" => "C1",
          "checked" => ["Original brief and README.md contain no export format"],
          "why_needed" =>
            "The requested integration accepts only one format and guessing would change the result."
        }
      })

    {:ok, next} = BoardControl.next_item(e)
    assert :ok = BoardControl.Decision.validate(output, input, next)

    for bad <- [
          Map.put(output, "question", nil),
          put_in(output, ["question", "kind"], "ordinary_naming"),
          put_in(output, ["question", "checked"], []),
          put_in(output, ["question", "criterion_id"], "C99"),
          put_in(output, ["question", "why_needed"], " "),
          put_in(output, ["question", "permissions"], ["push"])
        ] do
      assert {:error, :invalid_controller_output} =
               BoardControl.Decision.validate(bad, input, next)
    end

    dispatch(fake_decision: fn current -> Map.put(output, "revision", current["revision"]) end)
    [q] = BoardControl.Plans.questions(e.id)
    assert q.question =~ "Already checked: Original brief"
    assert BoardControl.get(e.id).state == "attention"
    authorization = BoardControl.get(e.id).delivery_authorization_json
    link_delivery(board, project)
    {:ok, view, _} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(
             view,
             "#board-question-#{q.id}",
             "Should the required export use CSV or JSON?"
           )

    view |> form("#answer-#{q.id}", question: %{answer: "CSV"}) |> render_change()
    send(view.pid, :tick)
    assert has_element?(view, "#answer-text-#{q.id}", "CSV")
    view |> form("#answer-#{q.id}", question: %{answer: "CSV"}) |> render_submit()
    assert [%{answer: "CSV"}] = BoardControl.Plans.questions(e.id)
    assert BoardControl.get(e.id).state == "running"
    assert BoardControl.get(e.id).delivery_authorization_json == authorization
  end

  test "recovery refuses changed stage artifacts and unverified cleanup", %{board: board} do
    {_e, skeleton} = recovery_run(board)
    assert {:recovering, _} = fail_delivery(skeleton, :provider_unavailable)
    {:ok, stage} = BoardControl.Recovery.replay(skeleton, "specification", 0)
    path = Path.join([skeleton.environment.run_dir, "artifacts", stage.output.artifact["path"]])
    File.write!(path, "Changed saved evidence")

    assert {:error, :recovery_artifact_changed} =
             BoardControl.Recovery.replay(skeleton, "specification", 0)

    {:ok, _} =
      Cuckoding.Execution.EventStore.append(skeleton.run.id, %{
        event_type: "process.cleanup_failed",
        public_summary: "Fixture unverified cleanup",
        payload: %{}
      })

    assert {:error, :recovery_process_unverified} =
             Cuckoding.GuidedRun.resume(skeleton.run.id, async: false)

    assert BoardControl.Recovery.pending(skeleton.run).checkpoint_json["recovery"]["state"] ==
             "pending"
  end

  test "plan correction is bounded and Skip during review cannot bypass planning", %{board: board} do
    original = task(board.id, "Original", 1)
    e = autonomous(board.id)
    dispatch()

    dispatch(
      fake_decision: fn input ->
        Cuckoding.BoardControl.Plans.fake_output(input)
        |> Map.merge(%{"verdict" => "revise", "comments" => ["Clarify test evidence"]})
      end
    )

    assert BoardControl.get(e.id).phase == "planning"
    assert [%{state: "rejected"}] = Cuckoding.BoardControl.Plans.revisions(e.id)
    dispatch()
    current = BoardControl.get(e.id)
    assert current.phase == "plan_review"

    assert {:ok, skipped} =
             BoardControl.control(e.id, current.revision, "skip", "skip-review", confirmed: true)

    assert skipped.phase == "planning"
    assert Repo.aggregate(from(r in Run, where: r.task_id == ^original.id), :count) == 0

    assert Enum.map(Cuckoding.BoardControl.Plans.revisions(e.id), & &1.state) == [
             "rejected",
             "invalidated"
           ]
  end

  test "planning and coordination cannot reset the saved Speculator token budget", %{board: board} do
    e = autonomous(board.id)
    dispatch()
    [session] = Cuckoding.BoardControl.Statistics.snapshot(BoardControl.get(e.id)).sessions

    usage = %Cuckoding.Adapters.Types.Usage{
      source: "provider",
      confidence: "reported",
      input_tokens: 200_001
    }

    assert {:ok, _} =
             Cuckoding.Telemetry.Accounting.record_usage(session.id, "planner-budget", usage)

    dispatch()
    dispatch()
    current = BoardControl.get(e.id)
    assert current.state == "attention"
    assert length(Cuckoding.BoardControl.Statistics.snapshot(current).sessions) == 2
    assert current.head_sha == e.base_sha
  end

  test "questions preserve entered answers across live updates and save without expanding grants",
       %{board: board, conn: conn} do
    e = autonomous(board.id)
    dispatch()
    dispatch()
    dispatch(fake_decision: decision("ask", nil))
    [q] = Cuckoding.BoardControl.Plans.questions(e.id)
    {:ok, view, _} = live(conn, ~p"/boards/#{board.id}")

    html =
      view
      |> form("#answer-#{q.id}", question: %{answer: "Keep the existing scope"})
      |> render_change()

    assert html =~ "Keep the existing scope"
    send(view.pid, :board_tick)
    assert render(view) =~ "Keep the existing scope"

    view
    |> form("#answer-#{q.id}", question: %{answer: "Keep the existing scope"})
    |> render_submit()

    assert [%{answer: "Keep the existing scope"}] = Cuckoding.BoardControl.Plans.questions(e.id)
    assert BoardControl.get(e.id).snapshot_json == e.snapshot_json
  end

  defp ready_for_final_review(
         board,
         commands \\ [
           %{"name" => "integrity", "phase" => "check", "command" => ["git", "diff", "--check"]}
         ]
       ) do
    {:ok, e} = BoardControl.prepare_goal(board.id, "A reviewed tested change", "prepare-final")

    dispatch(
      fake_decision: fn input ->
        BoardControl.Plans.fake_output(input) |> Map.put("commands", commands)
      end
    )

    dispatch()
    {:ok, preview} = BoardControl.delivery_preview(e.id)
    {:ok, _} = BoardControl.activate_goal(e.id, preview.digest, "run-final")
    for _ <- 1..4, do: dispatch()
    assert %{phase: "final_review", state: "running"} = BoardControl.get(e.id)
    BoardControl.get(e.id)
  end

  defp fixture_node(body \\ "printf 'fixture node version\\n'") do
    home = Path.join(System.tmp_dir!(), "goal-tool-home-#{System.unique_integer([:positive])}")
    path = Path.join(home, ".volta/tools/image/node/99.0.0/bin/node")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "#!/bin/sh\n#{body}\n")
    File.chmod!(path, 0o700)

    previous =
      Map.new(~w(CUCKODING_RUNTIME_HOME CUCKODING_TOOL_CANARY), &{&1, System.get_env(&1)})

    System.put_env("CUCKODING_RUNTIME_HOME", home)
    System.put_env("CUCKODING_TOOL_CANARY", "must-not-be-inherited")

    on_exit(fn ->
      restore_environment(previous)
      File.rm_rf!(home)
    end)

    path
  end

  defp restore_environment(previous) do
    Enum.each(previous, fn {key, value} ->
      if value, do: System.put_env(key, value), else: System.delete_env(key)
    end)
  end

  defp tool_plan(native) do
    fn input ->
      assert native in input["available_tools"]["node"]

      BoardControl.Plans.fake_output(input)
      |> Map.put("commands", [
        %{"name" => "tests", "phase" => "check", "command" => [native, "--test"]}
      ])
    end
  end

  defp recovery_run(board) do
    e = authorized_goal(board)
    dispatch()
    selected = BoardControl.get(e.id)
    {:ok, _} = Workflows.transition_task(selected.current_task_id, "ready", "fixture-ready")

    {:ok, prepared} =
      ProjectWorkflow.prepare_task(selected.current_task_id, board_execution_id: e.id)

    {:ok, _} = Cuckoding.Execution.transition_run(prepared.run.id, "running", "fixture-running")

    {:ok, _} =
      Cuckoding.Execution.EventStore.append(prepared.run.id, %{
        event_type: "run.completion_policy",
        public_summary: "Fixture uses authorized local completion",
        payload: %{
          "mode" => "local",
          "actor" => "board:#{e.id}",
          "release_handoff" => "requires_approval"
        }
      })

    {:ok, skeleton} = WalkingSkeleton.load(prepared.run.id)
    {e, skeleton}
  end

  defp authorized_goal(board) do
    {:ok, e} =
      BoardControl.prepare_goal(board.id, "A recoverable tested application", "prepare-recovery")

    dispatch()
    dispatch()
    {:ok, preview} = BoardControl.delivery_preview(e.id)
    {:ok, _} = BoardControl.activate_goal(e.id, preview.digest, "run-recovery")
    BoardControl.get(e.id)
  end

  defp repaired_plan(input, id) do
    task = Enum.find(input["queue"], &(&1["id"] == id))

    Map.merge(Map.take(input, ~w(execution_id revision)), %{
      "summary" => "Use a smaller implementation step after the retained turn-limit failure",
      "changes" => [
        %{
          "key" => id,
          "task_id" => id,
          "title" => task["title"],
          "description" =>
            task["description"] <>
              "\nImplement the smallest passing core before optional presentation work.",
          "priority" => task["priority"],
          "criteria" => ["C1"],
          "dependencies" => task["dependencies"],
          "replaces" => []
        }
      ]
    })
  end

  defp link_delivery(board, project) do
    {:ok, _} =
      Cuckoding.Execution.Commands.execute_once(
        %{
          idempotency_key: "project:#{project.id}:delivery-board",
          kind: "project.delivery_board",
          target_type: "project",
          target_id: project.id
        },
        fn _ -> {:ok, %{"board_id" => board.id}} end
      )
  end

  defp fail_delivery(skeleton, failure, options \\ []) do
    RunControl.track(skeleton.run.id, :workflow, fn ->
      WalkingSkeleton.run(
        skeleton,
        Keyword.merge(options,
          simulate_sleep_gap: false,
          role_adapters: %{
            "implementer" => %{
              adapter: RecoveryFailure,
              options: [failure: failure],
              version: "fixture"
            }
          }
        )
      )
    end)
  end

  defp make_recovery_due(run) do
    attempt = BoardControl.Recovery.pending(run)

    checkpoint =
      put_in(
        attempt.checkpoint_json,
        ["recovery", "next_eligible_at"],
        Cuckoding.Clock.wall_now() |> DateTime.add(-1, :second) |> DateTime.to_iso8601()
      )

    # Advance this fixture's durable clock boundary; production deadlines are never reset.
    {:ok, _} = Cuckoding.Execution.checkpoint_stage_attempt(attempt, checkpoint)
  end

  defp claim_recovery(run) do
    make_recovery_due(run)
    assert {:ok, _} = RunControl.admit(run.id, fn -> BoardControl.Recovery.claim(run) end)
  end

  defp autonomous(board, overrides \\ %{}) do
    goal =
      Map.merge(
        %{"goal" => "Implement the approved goal", "criteria" => "A reviewed change exists"},
        overrides
      )

    {:ok, preview} = BoardControl.preflight(board, [], goal)
    {:ok, e} = BoardControl.start(board, preview.digest, [], "autonomous", true, goal)
    e
  end

  defp decision(action, id) do
    fn input ->
      Map.merge(Map.take(input, ~w(execution_id revision)), %{
        "action" => action,
        "task_id" => id,
        "summary" => "Bounded fixture decision"
      })
    end
  end

  defp change(key, dependencies, replaces) do
    %{
      "key" => key,
      "task_id" => nil,
      "title" => key,
      "description" => "Test the approved behavior",
      "priority" => 1,
      "criteria" => ["C1"],
      "dependencies" => dependencies,
      "replaces" => replaces
    }
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
