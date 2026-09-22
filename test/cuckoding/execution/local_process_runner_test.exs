defmodule Cuckoding.Execution.LocalProcessRunnerTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Execution.LocalHostInspector
  alias Cuckoding.Execution.LocalProcessRunner
  alias Cuckoding.Execution.ProcessRecord
  alias Cuckoding.Execution.ProcessTerminator
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows

  @now ~U[2026-09-17 21:45:00.000000Z]

  setup do
    root = Path.join(System.tmp_dir!(), "cuckoding-runner-#{System.unique_integer([:positive])}")
    worktree = Path.join(root, "worktree")
    run_dir = Path.join(root, "run")
    File.mkdir_p!(worktree)
    File.mkdir_p!(run_dir)
    on_exit(fn -> File.rm_rf!(root) end)

    environment = environment_fixture(root, run_dir, worktree)
    assert {:ok, ^environment} = LocalProcessRunner.prepare(environment, [])
    {:ok, environment: environment}
  end

  test "uses only the allowlisted environment and redacts the complete output artifact",
       fixture do
    System.put_env("CUCKODING_AMBIENT_CANARY", "must-not-leak")
    on_exit(fn -> System.delete_env("CUCKODING_AMBIENT_CANARY") end)

    assert {:ok, env_result} =
             LocalProcessRunner.exec(
               fixture.environment,
               %{executable: "/usr/bin/env", args: []},
               env: %{"CUCKODING_TEST" => "allowed"},
               timeout: 2_000
             )

    assert env_result.exit_status == 0, inspect(env_result)
    assert env_result.output =~ "CUCKODING_TEST=allowed"
    refute env_result.output =~ "must-not-leak"

    secret = "runner-secret-canary"
    payload = String.duplicate("x", 100) <> secret

    assert {:ok, result} =
             LocalProcessRunner.exec(
               fixture.environment,
               %{executable: "/usr/bin/printf", args: [payload]},
               output_limit: 32,
               redact: [secret],
               timeout: 2_000
             )

    assert result.truncated?
    assert byte_size(result.output) == 32
    assert result.output_bytes > 32
    artifact = File.read!(result.artifact_path)
    assert artifact =~ "[REDACTED]"
    refute artifact =~ secret

    assert {:ok, events} = LocalProcessRunner.stream_events(result.process, [])
    assert Enum.any?(events, &(&1.event_type == "process.output_truncated"))
  end

  test "kills the owned process group without leaving a descendant", fixture do
    child_pid_path = Path.join(fixture.environment.worktree_path, "child.pid")

    {start_us, start_result} =
      :timer.tc(fn ->
        LocalProcessRunner.start(
          fixture.environment,
          %{
            executable: "/bin/sh",
            args: ["-c", "sleep 60 & echo $! > child.pid; wait"]
          },
          timeout: :infinity,
          termination_grace_ms: 25
        )
      end)

    assert {:ok, handle} = start_result
    assert start_us < 1_000_000, "start took #{div(start_us, 1_000)}ms"

    on_exit(fn ->
      if Process.alive?(handle.worker), do: LocalProcessRunner.stop(handle)
    end)

    assert :ok = wait_for_file(child_pid_path)
    child_pid = child_pid_path |> File.read!() |> String.trim() |> String.to_integer()
    assert {:ok, _identity} = LocalHostInspector.process_identity(child_pid, [])
    {inspect_us, inspect_result} = :timer.tc(fn -> LocalProcessRunner.inspect(handle.process) end)
    assert {:ok, sample} = inspect_result
    assert inspect_us < 1_000_000, "inspect took #{div(inspect_us, 1_000)}ms"
    assert sample.status == :matching
    assert sample.process_count >= 1

    {stop_us, stop_result} = :timer.tc(fn -> LocalProcessRunner.stop(handle) end)
    assert {:ok, result} = stop_result
    assert stop_us < 1_000_000, "stop took #{div(stop_us, 1_000)}ms"
    assert result.exit_status != 0

    Process.sleep(25)
    assert LocalHostInspector.groups_empty?(sample.pgids)
    assert :gone = LocalHostInspector.process_identity(child_pid, [])

    assert {:ok, events} = LocalProcessRunner.stream_events(result.process, [])
    assert Enum.any?(events, &(&1.event_type == "process.signal"))
  end

  test "cleans up same-group children when the command exits normally", fixture do
    child_pid_path = Path.join(fixture.environment.worktree_path, "child.pid")

    assert {:ok, handle} =
             LocalProcessRunner.start(
               fixture.environment,
               %{
                 executable: "/bin/sh",
                 args: ["-c", "sleep 60 >/dev/null 2>&1 & echo $! > child.pid; exit 0"]
               },
               timeout: :infinity,
               termination_grace_ms: 25
             )

    assert :ok = wait_for_file(child_pid_path)
    child_pid = child_pid_path |> File.read!() |> String.trim() |> String.to_integer()
    assert {:ok, identity} = LocalHostInspector.process_identity(child_pid, [])

    on_exit(fn ->
      if LocalHostInspector.process_identity(child_pid, []) == {:ok, identity} do
        System.cmd("/bin/kill", ["-TERM", Integer.to_string(child_pid)])
      end
    end)

    assert {:ok, result} = LocalProcessRunner.result(handle)
    assert result.exit_status == 0
    assert :gone = LocalHostInspector.process_identity(child_pid, [])
    assert LocalHostInspector.groups_empty?([handle.process.pgid])
    assert {:ok, events} = LocalProcessRunner.stream_events(result.process, [])
    assert Enum.any?(events, &(&1.event_type == "process.signal"))
  end

  test "samples CPU, RSS, process count, and listening ports for the owned group", fixture do
    port_path = Path.join(fixture.environment.worktree_path, "listener.port")

    assert {:ok, handle} =
             LocalProcessRunner.start(
               fixture.environment,
               %{
                 executable: "/usr/bin/ruby",
                 args: [
                   "-rsocket",
                   "-e",
                   "server=TCPServer.new('127.0.0.1',0); File.write('listener.port', server.addr[1]); sleep 60"
                 ]
               },
               timeout: :infinity,
               termination_grace_ms: 25
             )

    on_exit(fn ->
      if Process.alive?(handle.worker), do: LocalProcessRunner.stop(handle)
    end)

    assert :ok = wait_for_file(port_path)
    port = port_path |> File.read!() |> String.to_integer()

    assert {:ok, sample} = LocalHostInspector.resource_sample(handle.process)
    assert sample.status == :matching
    assert sample.cpu_nanos >= 0
    assert sample.memory_bytes > 0
    assert sample.process_count >= 1
    assert port in sample.open_ports_json

    assert {:ok, _result} = LocalProcessRunner.stop(handle)
  end

  test "timeouts run the termination ladder and persist the outcome", fixture do
    assert {:ok, result} =
             LocalProcessRunner.exec(
               fixture.environment,
               %{executable: "/bin/sleep", args: ["60"]},
               timeout: 50,
               termination_grace_ms: 25
             )

    assert result.timed_out?
    assert result.exit_status != 0
    assert {:ok, events} = LocalProcessRunner.stream_events(result.process, [])
    assert Enum.any?(events, &(&1.event_type == "process.timeout"))
    assert Enum.any?(events, &(&1.event_type == "process.signal"))
  end

  test "noninteractive commands receive stdin EOF", fixture do
    assert {:ok, result} =
             LocalProcessRunner.exec(
               fixture.environment,
               %{
                 executable: "/usr/bin/ruby",
                 args: ["-e", "puts STDIN.read.empty?"]
               },
               timeout: 2_000
             )

    assert result.exit_status == 0
    assert result.output == "true\n"
  end

  test "refuses to signal a reused PID identity", fixture do
    assert {:ok, handle} =
             LocalProcessRunner.start(
               fixture.environment,
               %{executable: "/bin/sleep", args: ["60"]},
               timeout: :infinity,
               termination_grace_ms: 25
             )

    tampered = %{handle.process | start_identity: "different process"}

    assert {:error, :process_identity_mismatch} =
             ProcessTerminator.terminate(tampered, grace_ms: 1)

    assert {:error, :process_identity_unavailable} =
             ProcessTerminator.terminate_after_exit(handle.process, grace_ms: 1)

    assert {:ok, %{status: :matching}} = LocalProcessRunner.inspect(handle.process)
    assert {:ok, _result} = LocalProcessRunner.stop(handle)
  end

  test "rejects failed or malformed process-table snapshots" do
    assert {:error, :process_inspection_failed} = LocalHostInspector.process_rows({"", 1})
    assert {:error, :process_inspection_failed} = LocalHostInspector.process_rows({"", 0})

    assert {:error, :process_inspection_failed} =
             LocalHostInspector.process_rows({"123 1 123 4\nmalformed\n", 0})

    assert {:ok, [%{pid: 123, pgid: 123}]} =
             LocalHostInspector.process_rows({"123 1 123 4\n", 0})
  end

  test "destroy stops every running process owned by the environment", fixture do
    assert {:ok, handle} =
             LocalProcessRunner.start(
               fixture.environment,
               %{executable: "/bin/sleep", args: ["60"]},
               timeout: :infinity,
               termination_grace_ms: 25
             )

    assert :ok = LocalProcessRunner.destroy(fixture.environment, grace_ms: 25)
    assert :gone = LocalHostInspector.process_identity(handle.process.pid, [])
    assert Repo.get!(ProcessRecord, handle.process.id).state == "failed"
  end

  test "rejects sensitive and undeclared environment keys", fixture do
    command = %{executable: "/usr/bin/env", args: []}

    assert {:ok, %{output: output}} =
             LocalProcessRunner.exec(fixture.environment, command,
               env: %{"AGENT_CLI_CREDENTIAL_STORE" => "file"},
               environment_allowlist: ["AGENT_CLI_CREDENTIAL_STORE"]
             )

    assert output =~ "AGENT_CLI_CREDENTIAL_STORE=file"

    assert {:error, {:sensitive_environment_key, "AGENT_CLI_CREDENTIAL_STORE"}} =
             LocalProcessRunner.start(fixture.environment, command,
               env: %{"AGENT_CLI_CREDENTIAL_STORE" => "keychain"},
               environment_allowlist: ["AGENT_CLI_CREDENTIAL_STORE"]
             )

    assert {:error, {:sensitive_environment_key, "API_TOKEN"}} =
             LocalProcessRunner.start(fixture.environment, command, env: %{"API_TOKEN" => "nope"})

    assert {:error, {:environment_key_not_allowed, "RANDOM_SETTING"}} =
             LocalProcessRunner.start(fixture.environment, command,
               env: %{"RANDOM_SETTING" => "nope"}
             )
  end

  defp environment_fixture(root, run_dir, worktree) do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Runner project #{suffix}",
        repo_path: root,
        default_branch: "main",
        workspace_root: root,
        port_range_start: 43_000,
        port_range_end: 43_100
      })

    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: String.pad_leading(Integer.to_string(suffix, 16), 64, "0"),
        config_json: %{"version" => 1},
        trusted_at: @now
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: %{"stages" => [%{"key" => "implementation", "role" => "implementer"}]},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Board",
        concurrency_limit: 1
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: "Task", position: 1})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: policy.id,
        plugin_snapshot_json: %{},
        branch: "feature/runner-#{suffix}",
        base_sha: String.duplicate("a", 40)
      })

    {:ok, environment} =
      Execution.create_environment(%{
        run_id: run.id,
        runner_key: "local_process",
        kind: "local_process",
        worktree_path: worktree,
        run_dir: run_dir,
        base_sha: run.base_sha,
        head_sha: run.base_sha,
        ports_json: %{},
        isolation_claims_json: %{"sandbox" => false}
      })

    environment
  end

  defp wait_for_file(path, attempts \\ 50)
  defp wait_for_file(_path, 0), do: {:error, :file_timeout}

  defp wait_for_file(path, attempts) do
    if File.exists?(path) do
      :ok
    else
      Process.sleep(20)
      wait_for_file(path, attempts - 1)
    end
  end
end
