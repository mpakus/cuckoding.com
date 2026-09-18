defmodule Cuckoding.Plugins.ContractsTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Identifier
  alias Cuckoding.PluginConformance
  alias Cuckoding.Plugins.Capability
  alias Cuckoding.Plugins.Contracts
  alias Cuckoding.Plugins.Manifest
  alias Cuckoding.Plugins.Measurement
  alias Cuckoding.Plugins.Plugin
  alias Cuckoding.Plugins.Registry
  alias Cuckoding.Plugins.Result
  alias Cuckoding.Projects
  alias Cuckoding.Workflows

  @now ~U[2026-09-18 13:00:00.000000Z]

  defmodule NumericOutput do
    def sample(_request, _context), do: {:ok, %Result{data: %{"memory" => 12}}}
  end

  defmodule UnlabeledMeasurement do
    def sample(_request, _context) do
      {:ok,
       %Result{
         measurements: [
           %Measurement{name: "memory", value: 12, unit: "bytes", source: "guessed"}
         ]
       }}
    end
  end

  defmodule LeakyNotifier do
    def notify(_request, _context) do
      {:ok, %Result{data: %{"token" => "canary", "message" => "contains canary"}}}
    end
  end

  setup do
    run = run_fixture()

    contexts =
      Map.new(Contracts.list(), fn {kind, {_behaviour, _operations}} ->
        plugin = plugin_fixture(kind)

        assert {:ok, _activation} =
                 Registry.enable(plugin.id, "global", nil, %{
                   "permissions" => plugin.manifest_json["permissions"],
                   "approval_kind" => "standard",
                   "actor" => "conformance-test",
                   "reason" => "Exercise the plugin contract",
                   "config" => %{}
                 })

        assert {:ok, context} = Capability.issue(plugin.id, run.id)
        {kind, context}
      end)

    %{contexts: contexts, run: run}
  end

  test "every plugin kind declares a behaviour and passes its reusable fake suite", %{
    contexts: contexts
  } do
    fakes = %{
      "knowledge_backend" => Cuckoding.PluginFakes.KnowledgeBackend,
      "shell_filter" => Cuckoding.PluginFakes.ShellFilter,
      "instruction_skill" => Cuckoding.PluginFakes.InstructionSkill,
      "mcp_server" => Cuckoding.PluginFakes.McpServer,
      "runner" => Cuckoding.PluginFakes.Runner,
      "metric_source" => Cuckoding.PluginFakes.MetricSource,
      "vcs_host" => Cuckoding.PluginFakes.VcsHost,
      "secret_store" => Cuckoding.PluginFakes.SecretStore,
      "notifier" => Cuckoding.PluginFakes.Notifier
    }

    assert Enum.sort(Map.keys(fakes)) == Enum.sort(Manifest.kinds())

    for {kind, implementation} <- fakes do
      assert :ok = PluginConformance.check(kind, implementation, contexts[kind])
    end

    assert_received {:plugin_fake_called, "runner", :prepare, _run_id}
    assert_received {:plugin_fake_called, "notifier", :notify, _run_id}
  end

  test "capabilities reject run tampering and become invalid when activation is disabled", %{
    contexts: contexts
  } do
    context = contexts["notifier"]
    tampered = %{context | run_id: Identifier.generate()}

    assert {:error, :invalid_plugin_capability} =
             Contracts.call("notifier", Cuckoding.PluginFakes.Notifier, :notify, %{}, tampered)

    assert {:ok, _activation} =
             Registry.disable(
               context.plugin_id,
               "global",
               nil,
               "conformance-test",
               "Revoke the fixture grant"
             )

    assert {:error, :invalid_plugin_capability} =
             Contracts.call("notifier", Cuckoding.PluginFakes.Notifier, :notify, %{}, context)

    refute inspect(context) =~ context.capability_token
    assert inspect(context) =~ "[REDACTED]"
  end

  test "numeric output requires a measured, reported, or estimated label", %{contexts: contexts} do
    context = contexts["metric_source"]

    assert {:error, :unlabeled_numeric_plugin_output} =
             Contracts.call("metric_source", NumericOutput, :sample, %{}, context)

    assert {:error, :invalid_plugin_measurement} =
             Contracts.call("metric_source", UnlabeledMeasurement, :sample, %{}, context)
  end

  test "changing approved plugin configuration invalidates an issued capability", %{
    contexts: contexts
  } do
    context = contexts["notifier"]

    assert {:ok, _activation} =
             Registry.enable(context.plugin_id, "global", nil, %{
               "permissions" => context.permissions,
               "approval_kind" => "standard",
               "actor" => "conformance-test",
               "reason" => "Change the notification channel",
               "config" => %{"channel" => "secondary"}
             })

    assert {:error, :invalid_plugin_capability} =
             Contracts.call("notifier", Cuckoding.PluginFakes.Notifier, :notify, %{}, context)
  end

  test "public plugin output is recursively redacted", %{contexts: contexts} do
    assert {:ok, result} =
             Contracts.call(
               "notifier",
               LeakyNotifier,
               :notify,
               %{},
               contexts["notifier"],
               secrets: ["canary"]
             )

    assert result.data == %{"token" => "[REDACTED]", "message" => "contains [REDACTED]"}
  end

  test "secret-store private values are usable in memory but hidden from inspection", %{
    contexts: contexts
  } do
    assert {:ok, result} =
             Contracts.call(
               "secret_store",
               Cuckoding.PluginFakes.SecretStore,
               :fetch,
               %{},
               contexts["secret_store"]
             )

    assert result.private == %{"value" => "fixture"}
    refute inspect(result) =~ "fixture"
    assert inspect(result) =~ "[REDACTED]"
  end

  defp plugin_fixture(kind) do
    id = Identifier.generate()
    key = "fake-" <> String.replace(kind, "_", "-")

    permissions = %{
      "host_process" => false,
      "network" => "none",
      "read_paths" => [],
      "write_paths" => [],
      "secrets" => []
    }

    manifest = %{
      "kind" => kind,
      "capabilities" => [kind <> ".fixture"],
      "permissions" => permissions,
      "scopes" => ["project", "board", "role", "stage"]
    }

    %Plugin{}
    |> Plugin.changeset(%{
      id: id,
      key: key,
      name: "Fake #{kind}",
      kind: kind,
      version: "1.0.0",
      source: "bundled",
      manifest_path: "/fixtures/#{key}/plugin.yml",
      manifest_hash: String.pad_leading(Integer.to_string(:erlang.phash2(key), 16), 64, "0"),
      manifest_json: manifest,
      detected_binaries_json: %{},
      health: "available",
      detected_at: @now
    })
    |> Repo.insert!()
  end

  defp run_fixture do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Plugin contracts #{suffix}",
        repo_path: "/tmp/plugin-contracts-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/plugin-contract-workspaces-#{suffix}",
        port_range_start: 55_000,
        port_range_end: 55_100
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
        name: "plugin-contracts",
        version: 1,
        definition_json: %{"stages" => [%{"key" => "implementation", "role" => "implementer"}]},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Plugin contracts",
        concurrency_limit: 1
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: "Conformance", position: 0})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        workflow_snapshot_json: workflow.definition_json,
        policy_snapshot_id: config.id,
        plugin_snapshot_json: %{},
        branch: "feature/plugin-contracts-#{suffix}",
        base_sha: String.duplicate("a", 40)
      })

    run
  end
end
