defmodule Cuckoding.ShellTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Shell
  alias Cuckoding.Shell.QuitPolicy
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.Board

  @now ~U[2026-09-18 15:30:00.000000Z]

  @tag recovery_drill: true
  test "quit policy pauses admission and hibernates active runs" do
    %{run: run, board: board, environment: environment} = running_run_fixture()

    assert :ok = Shell.shutdown(policy: QuitPolicy)
    assert Repo.get!(Execution.Run, run.id).state == "hibernated"
    assert Repo.get!(Execution.Environment, environment.id).state == "hibernated"
    assert Repo.get!(Board, board.id).status == "paused"
  end

  test "quit refuses to stop a port-owning run without its live lease handle" do
    %{run: run, board: board, environment: environment} = running_run_fixture(58_050)

    assert {:error, {:hibernate_failed, board_id, _reason}} =
             Shell.shutdown(policy: QuitPolicy)

    assert board_id == board.id

    assert Repo.get!(Execution.Run, run.id).state == "running"
    assert Repo.get!(Execution.Environment, environment.id).state == "prepared"
    assert Repo.get!(Board, board.id).status == "paused"
  end

  defp running_run_fixture(port \\ nil) do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Shell #{suffix}",
        repo_path: "/tmp/shell-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/shell-workspaces-#{suffix}",
        port_range_start: 58_000,
        port_range_end: 58_100
      })

    {:ok, config} =
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
        name: "shell",
        version: 1,
        definition_json: %{"stages" => [%{"key" => "run", "role" => "implementer"}]},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Shell",
        concurrency_limit: 1
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: "Shell", position: 0})
    {:ok, ready} = Workflows.transition_task(task.id, "ready", "shell:ready:#{task.id}")
    assert ready.result["outcome"] == "transitioned"

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        workflow_snapshot_json: workflow.definition_json,
        policy_snapshot_id: config.id,
        plugin_snapshot_json: %{},
        branch: "feature/shell-#{suffix}",
        base_sha: String.duplicate("a", 40)
      })

    {:ok, command} = Execution.transition_run(run.id, "running", "shell:run:#{run.id}")
    assert command.result["outcome"] == "transitioned"

    {:ok, environment} =
      Execution.create_environment(%{
        run_id: run.id,
        runner_key: "local_process",
        kind: "local_process",
        worktree_path: "/tmp/shell-worktree-#{suffix}",
        run_dir: "/tmp/shell-run-#{suffix}",
        base_sha: run.base_sha,
        ports_json: if(port, do: %{"preview" => port}, else: %{}),
        port: port,
        preview_url: if(port, do: "http://127.0.0.1:#{port}"),
        isolation_claims_json: %{}
      })

    %{run: Repo.get!(Execution.Run, run.id), board: board, environment: environment}
  end
end
