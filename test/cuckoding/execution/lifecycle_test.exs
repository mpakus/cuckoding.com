defmodule Cuckoding.Execution.LifecycleTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Execution.CommandPolicy
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.GitService
  alias Cuckoding.Execution.Leases
  alias Cuckoding.Execution.Lifecycle
  alias Cuckoding.Execution.LocalProcessRunner
  alias Cuckoding.Execution.PortAllocator
  alias Cuckoding.Execution.Preview
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows

  @now ~U[2026-09-17 23:00:00.000000Z]

  setup do
    root =
      Path.join(System.tmp_dir!(), "cuckoding-lifecycle-#{System.unique_integer([:positive])}")

    repo = Path.join(root, "repo")
    workspace = Path.join(root, "workspaces")
    fixture = Path.expand("../../fixtures/preview_project", __DIR__)
    File.mkdir_p!(root)
    File.cp_r!(fixture, repo)
    git!(repo, ["init", "-b", "main"])
    git!(repo, ["config", "user.email", "fixture@example.test"])
    git!(repo, ["config", "user.name", "Fixture"])
    git!(repo, ["add", "--all"])
    git!(repo, ["commit", "-m", "base"])

    first_port = free_range(4)
    domain = domain_fixture(repo, workspace, first_port, first_port + 3)

    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, domain: domain}
  end

  test "hibernate, relaunch, and resume preserve one stage execution", %{domain: domain} do
    lifecycle = running_environment(domain, "feature/lifecycle")
    artifact = Path.join([lifecycle.environment.run_dir, "artifacts", "review.txt"])
    File.write!(artifact, "retained evidence\n")

    assert {:ok, allocation} =
             PortAllocator.allocate(domain.project, lifecycle.environment)

    assert {:ok, service} = Preview.start(lifecycle.run, allocation, termination_grace_ms: 25)
    assert :ok = await_health(service)

    assert {:ok, paused} =
             Lifecycle.pause(
               lifecycle.run,
               allocation.environment,
               "pause-#{lifecycle.run.id}",
               checkpoint: fn attempt ->
                 {:ok, %{"attempt_id" => attempt.id, "summary" => "paused safely"}}
               end
             )

    assert paused.stage_attempt.id == lifecycle.attempt.id
    assert paused.stage_attempt.checkpoint_json["summary"] == "paused safely"
    assert Repo.get!(Run, lifecycle.run.id).state == "paused"
    assert {:ok, %{status: :matching}} = LocalProcessRunner.inspect(service.handle.process)

    assert {:ok, hibernated} =
             Lifecycle.hibernate(
               Repo.get!(Run, lifecycle.run.id),
               Repo.get!(Environment, lifecycle.environment.id),
               "hibernate-#{lifecycle.run.id}",
               allocation: allocation,
               checkpoint: fn attempt ->
                 {:ok, %{"attempt_id" => attempt.id, "summary" => "ready to resume"}}
               end,
               termination_grace_ms: 25
             )

    assert hibernated.environment.state == "hibernated"
    assert is_nil(hibernated.environment.port)
    refute Leases.active_for("port", "tcp:127.0.0.1:#{allocation.environment.port}")
    assert Repo.get!(Run, lifecycle.run.id).state == "hibernated"

    assert Repo.get!(StageAttempt, lifecycle.attempt.id).checkpoint_json["summary"] ==
             "ready to resume"

    events =
      RunEvent
      |> Repo.all()
      |> Enum.filter(&(&1.run_id == lifecycle.run.id))

    checkpoint_sequences =
      for event <- events, event.event_type == "stage.checkpointed", do: event.sequence

    signal_sequences =
      for event <- events, event.event_type == "process.signal", do: event.sequence

    assert Enum.max(checkpoint_sequences) < Enum.min(signal_sequences)

    # Reloading only durable identifiers models the next application process.
    reloaded_run = Repo.get!(Run, lifecycle.run.id)
    reloaded_environment = Repo.get!(Environment, lifecycle.environment.id)
    marker_path = Path.join(reloaded_environment.run_dir, "run.json")
    marker = File.read!(marker_path)

    changed_marker =
      marker |> Jason.decode!() |> Map.put("policy_hash", String.duplicate("0", 64))

    File.write!(marker_path, Jason.encode!(changed_marker))

    assert {:error, {:resume_blocked, :ownership_marker_changed}} =
             Lifecycle.resume(
               reloaded_run,
               reloaded_environment,
               "blocked-resume-#{lifecycle.run.id}"
             )

    assert is_nil(Repo.get!(Environment, lifecycle.environment.id).port)
    File.write!(marker_path, marker)
    test_pid = self()

    assert {:ok, resumed} =
             Lifecycle.resume(
               reloaded_run,
               reloaded_environment,
               "resume-#{lifecycle.run.id}",
               resume_stage: fn attempt, fresh_allocation ->
                 send(
                   test_pid,
                   {:resumed, attempt.id, attempt.checkpoint_json, fresh_allocation.lease.id}
                 )

                 {:ok, :native_session_resumed}
               end
             )

    assert_receive {:resumed, attempt_id, %{"summary" => "ready to resume"}, new_lease_id}
    assert attempt_id == lifecycle.attempt.id
    refute new_lease_id == allocation.lease.id
    assert resumed.stage_attempt.id == lifecycle.attempt.id
    assert resumed.resume_result == :native_session_resumed
    assert resumed.allocation.environment.state == "running"
    assert Repo.aggregate(StageAttempt, :count, :id) == 1
    assert Repo.get!(Run, lifecycle.run.id).state == "running"

    sibling = Path.join([domain.workspace, domain.project.id, "another-run"])
    File.mkdir_p!(sibling)
    sibling_file = Path.join(sibling, "keep.txt")
    File.write!(sibling_file, "not owned by this run\n")

    assert {:ok, cleanup} =
             Lifecycle.destroy(
               Repo.get!(Run, lifecycle.run.id),
               Repo.get!(Environment, lifecycle.environment.id),
               "destroy-#{lifecycle.run.id}",
               allocation: resumed.allocation,
               grace_ms: 25
             )

    refute File.exists?(lifecycle.environment.worktree_path)
    assert File.read!(artifact) == "retained evidence\n"
    assert File.read!(sibling_file) == "not owned by this run\n"
    assert Enum.any?(cleanup.retained_artifacts, &(&1["path"] == "review.txt"))
    assert cleanup.environment.state == "stopped"
    assert Repo.get!(Run, lifecycle.run.id).state == "cancelled"
  end

  test "checkpoint failure leaves the owned process running", %{domain: domain} do
    lifecycle = running_environment(domain, "feature/checkpoint-failure")
    assert {:ok, allocation} = PortAllocator.allocate(domain.project, lifecycle.environment)
    assert {:ok, service} = Preview.start(lifecycle.run, allocation, termination_grace_ms: 25)
    assert :ok = await_health(service)

    on_exit(fn ->
      LocalProcessRunner.destroy(allocation.environment, grace_ms: 25)
      PortAllocator.release(allocation, "stopped")
    end)

    assert {:error, :checkpoint_failed} =
             Lifecycle.hibernate(
               lifecycle.run,
               allocation.environment,
               "failed-hibernate-#{lifecycle.run.id}",
               allocation: allocation,
               checkpoint: fn _attempt -> {:error, :checkpoint_failed} end,
               termination_grace_ms: 25
             )

    assert Repo.get!(Run, lifecycle.run.id).state == "running"
    assert {:ok, %{status: :matching}} = LocalProcessRunner.inspect(service.handle.process)
    assert Leases.active_for("port", "tcp:127.0.0.1:#{allocation.environment.port}")
  end

  test "cleanup refuses changed ownership and dirty worktrees", %{domain: domain} do
    lifecycle = prepared_environment(domain, "feature/cleanup-guard")
    sentinel = Path.join(lifecycle.environment.worktree_path, "sentinel.txt")
    File.write!(sentinel, "keep\n")

    assert {:error, :dirty_worktree} = GitService.cleanup(lifecycle.environment)
    assert File.read!(sentinel) == "keep\n"

    File.rm!(sentinel)
    marker = Path.join(lifecycle.environment.run_dir, "run.json")

    ownership =
      marker |> File.read!() |> Jason.decode!() |> Map.put("run_id", Ecto.UUID.generate())

    File.write!(marker, Jason.encode!(ownership))

    assert {:error, {:ownership_drift, :ownership_marker_changed}} =
             GitService.cleanup(lifecycle.environment)

    assert File.dir?(lifecycle.environment.worktree_path)
  end

  defp running_environment(domain, branch) do
    lifecycle = prepared_environment(domain, branch)
    task = Repo.get!(Cuckoding.Workflows.Task, lifecycle.run.task_id)
    {:ok, _command} = Workflows.transition_task(task.id, "ready", "ready-#{task.id}")

    {:ok, _command} =
      Execution.transition_run(lifecycle.run.id, "running", "start-#{lifecycle.run.id}")

    {:ok, attempt} =
      Execution.create_stage_attempt(%{
        run_id: lifecycle.run.id,
        stage_key: "implement",
        attempt: 1,
        role_key: "implementer",
        role_kind: "agent"
      })

    %{lifecycle | run: Repo.get!(Run, lifecycle.run.id), attempt: attempt}
  end

  defp prepared_environment(domain, branch) do
    position = System.unique_integer([:positive])

    {:ok, task} =
      Workflows.create_task(%{
        board_id: domain.board.id,
        title: "Lifecycle #{position}",
        position: position
      })

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: domain.policy.id,
        plugin_snapshot_json: %{},
        branch: branch,
        base_sha: domain.base_sha
      })

    {:ok, environment} = GitService.prepare(domain.project, run)
    {:ok, ^environment} = LocalProcessRunner.prepare(environment, [])
    %{run: run, environment: environment, attempt: nil}
  end

  defp domain_fixture(repo, workspace, first_port, last_port) do
    {:ok, loaded} = CommandPolicy.load_project(Path.join(repo, ".cuckoding/project.yml"))
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Lifecycle project #{suffix}",
        repo_path: repo,
        default_branch: "main",
        workspace_root: workspace,
        port_range_start: first_port,
        port_range_end: last_port
      })

    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: loaded.source_hash,
        config_json: loaded.config,
        trusted_at: @now
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: %{"stages" => []},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Board",
        concurrency_limit: 4
      })

    %{
      project: project,
      policy: policy,
      board: board,
      base_sha: git!(repo, ["rev-parse", "HEAD"]),
      workspace: workspace
    }
  end

  defp free_range(size) do
    Enum.find(46_000..60_000, fn first ->
      Enum.all?(first..(first + size - 1), &PortAllocator.available?/1)
    end) || raise "no consecutive loopback ports available"
  end

  defp await_health(service, attempts \\ 50)
  defp await_health(_service, 0), do: {:error, :health_timeout}

  defp await_health(service, attempts) do
    case Preview.health(service, connect_timeout: 100, request_timeout: 100) do
      {:ok, :healthy} ->
        :ok

      _other ->
        Process.sleep(20)
        await_health(service, attempts - 1)
    end
  end

  defp git!(root, args) do
    case System.cmd("/usr/bin/git", ["-C", root | args], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git failed (#{status}): #{output}"
    end
  end
end
