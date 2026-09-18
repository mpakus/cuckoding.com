defmodule Cuckoding.Plugins.ContainerRunnerStubTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Identifier
  alias Cuckoding.PluginConformance
  alias Cuckoding.Plugins.Activation
  alias Cuckoding.Plugins.Capability
  alias Cuckoding.Plugins.ContainerRunnerStub
  alias Cuckoding.Plugins.Manifest
  alias Cuckoding.Plugins.Plugin
  alias Cuckoding.Projects
  alias Cuckoding.Workflows

  @now ~U[2026-09-18 15:00:00.000000Z]

  test "stub passes runner conformance while remaining visibly non-selectable" do
    run = run_fixture()
    plugin = plugin_fixture()
    activation = activation_fixture(plugin)

    assert {:ok, context} = Capability.issue(plugin.id, run.id)
    assert :ok = PluginConformance.check("runner", ContainerRunnerStub, context)

    assert {:ok, result} = ContainerRunnerStub.prepare(%{"backend" => "orbstack"}, context)
    assert result.data["status"] == "not_implemented"
    refute result.data["selectable"]
    assert result.data["git_strategy"] == "host_side"
    assert activation.enabled
    assert Manifest.isolation_label([]) == "No container isolation declared"
  end

  defp plugin_fixture do
    manifest = %{
      "capabilities" => ["runner.contract"],
      "permissions" => %{
        "host_process" => true,
        "network" => "none",
        "read_paths" => ["${RUN_WORKTREE}"],
        "write_paths" => ["${RUN_WORKTREE}", "${RUN_DIR}"],
        "secrets" => []
      },
      "scopes" => ["project", "board", "role", "stage"],
      "isolation_claims" => []
    }

    %Plugin{}
    |> Plugin.changeset(%{
      id: Identifier.generate(),
      key: "container-runner-test",
      name: "Container runner test",
      kind: "runner",
      version: "0.1.0",
      source: "bundled",
      manifest_path: "/fixture/plugin.yml",
      manifest_hash: String.duplicate("a", 64),
      manifest_json: manifest,
      detected_binaries_json: %{},
      health: "available",
      detected_at: @now
    })
    |> Repo.insert!()
  end

  defp activation_fixture(plugin) do
    %Activation{}
    |> Activation.changeset(%{
      id: Identifier.generate(),
      plugin_id: plugin.id,
      scope_type: "global",
      scope_id: nil,
      enabled: true,
      permissions_json: plugin.manifest_json["permissions"],
      config_json: %{},
      network: "none",
      approval_kind: "standard",
      approved_by: "test",
      approval_reason: "Runner conformance",
      approved_at: @now
    })
    |> Repo.insert!()
  end

  defp run_fixture do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Runner #{suffix}",
        repo_path: "/tmp/runner-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/runner-workspaces-#{suffix}",
        port_range_start: 57_000,
        port_range_end: 57_100
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
        name: "runner",
        version: 1,
        definition_json: %{
          "stages" => [%{"key" => "run", "role" => "implementer"}]
        },
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Runner",
        concurrency_limit: 1
      })

    {:ok, task} =
      Workflows.create_task(%{board_id: board.id, title: "Runner", position: 0})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        workflow_snapshot_json: workflow.definition_json,
        policy_snapshot_id: config.id,
        plugin_snapshot_json: %{},
        branch: "feature/runner-#{suffix}",
        base_sha: String.duplicate("a", 40)
      })

    run
  end
end
