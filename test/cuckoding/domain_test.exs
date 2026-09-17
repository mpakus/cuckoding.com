defmodule Cuckoding.DomainTest do
  use Cuckoding.DataCase, async: false
  use ExUnitProperties

  alias Cuckoding.Execution
  alias Cuckoding.Projects
  alias Cuckoding.Workflows

  @now ~U[2026-09-17 20:05:00.000000Z]

  test "command contexts create the core hierarchy with UUIDv7 identifiers" do
    domain = domain_fixture()

    for record <- Map.values(domain) do
      assert record.id =~
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    end

    assert domain.task.state == "draft"
    assert domain.run.state == "queued"
    assert domain.attempt.role_kind == "agent"
  end

  test "role kinds and system-role boundaries are enforced" do
    domain = domain_fixture()

    assert {:error, changeset} =
             Workflows.assign_role(%{
               board_id: domain.board.id,
               role_key: "release",
               role_kind: "system",
               adapter_key: "codex",
               settings_json: %{}
             })

    assert {"system roles cannot select an adapter or model", _options} =
             changeset.errors[:role_kind]

    assert {:error, changeset} =
             Workflows.assign_role(%{
               board_id: domain.board.id,
               role_key: "invalid",
               role_kind: "robot",
               settings_json: %{}
             })

    assert {"is invalid", _options} = changeset.errors[:role_kind]
  end

  test "boards reject workflows owned by another project" do
    first = domain_fixture()
    second = domain_fixture()

    assert {:error, :workflow_project_mismatch} =
             Workflows.create_board(%{
               project_id: first.project.id,
               workflow_version_id: second.workflow.id,
               name: "Mismatched",
               concurrency_limit: 1
             })
  end

  property "task dependencies reject every generated cycle" do
    check all(task_count <- integer(2..10), max_runs: 20) do
      domain = domain_fixture()

      tasks =
        for position <- 0..(task_count - 1) do
          {:ok, task} =
            Workflows.create_task(%{
              board_id: domain.board.id,
              title: "Task #{position}",
              position: position + 1
            })

          task
        end

      tasks
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [previous, current] ->
        assert {:ok, _dependency} = Workflows.add_dependency(current.id, previous.id)
      end)

      assert {:error, :dependency_cycle} =
               Workflows.add_dependency(List.first(tasks).id, List.last(tasks).id)
    end
  end

  test "active attempt, environment, and port constraints reject double ownership" do
    domain = domain_fixture()

    assert {:error, _changeset} =
             Execution.create_stage_attempt(%{
               run_id: domain.run.id,
               stage_key: "implementation",
               attempt: 2,
               role_key: "implementer",
               role_kind: "agent"
             })

    environment_attrs = %{
      run_id: domain.run.id,
      runner_key: "local",
      kind: "local_process",
      worktree_path: "/tmp/worktree-1",
      run_dir: "/tmp/run-1",
      base_sha: String.duplicate("a", 40),
      port: 41_001,
      ports_json: %{"preview" => 41_001},
      isolation_claims_json: %{"kind" => "trusted-host"}
    }

    assert {:ok, _environment} = Execution.create_environment(environment_attrs)
    assert {:error, _changeset} = Execution.create_environment(environment_attrs)

    assert {:error, :port_out_of_range} =
             Execution.create_environment(%{environment_attrs | port: 50_000})

    other = domain_fixture()

    assert {:error, _changeset} =
             Execution.create_environment(%{
               environment_attrs
               | run_id: other.run.id,
                 worktree_path: "/tmp/worktree-2",
                 run_dir: "/tmp/run-2"
             })
  end

  defp domain_fixture do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Project #{suffix}",
        repo_path: "/tmp/project-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/workspaces-#{suffix}",
        port_range_start: 41_000,
        port_range_end: 41_100
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
        name: "default",
        version: 1,
        definition_json: %{"stages" => []},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Board #{suffix}",
        concurrency_limit: 1
      })

    {:ok, task} =
      Workflows.create_task(%{board_id: board.id, title: "Task", position: 0})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        workflow_snapshot_json: workflow.definition_json,
        policy_snapshot_id: config.id,
        plugin_snapshot_json: %{},
        branch: "feature/#{suffix}",
        base_sha: String.duplicate("a", 40)
      })

    {:ok, attempt} =
      Execution.create_stage_attempt(%{
        run_id: run.id,
        stage_key: "implementation",
        attempt: 1,
        role_key: "implementer",
        role_kind: "agent"
      })

    %{
      project: project,
      config: config,
      workflow: workflow,
      board: board,
      task: task,
      run: run,
      attempt: attempt
    }
  end
end
