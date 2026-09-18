defmodule Cuckoding.Plugins.ReferenceTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Execution.Run
  alias Cuckoding.Plugins.Capability
  alias Cuckoding.Plugins.Contracts
  alias Cuckoding.Plugins.Plugin
  alias Cuckoding.Plugins.Reference.McpFilesystemReadonly
  alias Cuckoding.Plugins.Reference.Ponytail
  alias Cuckoding.Plugins.Reference.RTK
  alias Cuckoding.Plugins.Reference.XERJ
  alias Cuckoding.Plugins.Registry
  alias Cuckoding.Projects
  alias Cuckoding.Telemetry.OptimizationRecord
  alias Cuckoding.Workflows

  @now ~U[2026-09-18 14:00:00.000000Z]

  setup do
    fixture = domain_fixture()
    result = Registry.discover(detection_options())

    assert result.errors == []

    assert Enum.sort(Enum.map(result.plugins, & &1.key)) ==
             ~w(mcp-filesystem-readonly ponytail rtk xerj)

    contexts = enable_reference_plugins(fixture)
    %{fixture: fixture, contexts: contexts}
  end

  test "reference plugins use guarded configuration and source-labeled contributions", %{
    fixture: fixture,
    contexts: contexts
  } do
    assert {:ok, wrapped} =
             Contracts.call(
               "shell_filter",
               RTK,
               :wrap,
               %{"command_key" => "verify"},
               contexts.rtk
             )

    assert wrapped.data["executable"] == "rtk"
    assert wrapped.data["underlying_executable"] == "/usr/bin/true"

    assert {:ok, analytics} =
             Contracts.call(
               "shell_filter",
               RTK,
               :analytics,
               %{
                 "raw_units" => 100,
                 "optimized_units" => 40,
                 "estimation_method" => "bytes_divided_by_four"
               },
               contexts.rtk
             )

    assert Enum.all?(analytics.measurements, &(&1.source == "estimated"))
    optimization = Repo.one!(OptimizationRecord)
    assert optimization.run_id == fixture.run.id
    assert optimization.confidence == "estimated"

    assert {:ok, ponytail} =
             Contracts.call(
               "instruction_skill",
               Ponytail,
               :package,
               %{"mode" => "full"},
               contexts.ponytail
             )

    assert ponytail.data["policy_overlay"] |> Enum.member?("security")
    assert ponytail.data["instructions"] =~ "Minimalism never removes"

    assert {:error, :plugin_failed} =
             Contracts.call(
               "instruction_skill",
               Ponytail,
               :package,
               %{"mode" => "full", "waive" => ["security"]},
               contexts.ponytail
             )

    assert {:ok, search} =
             Contracts.call(
               "knowledge_backend",
               XERJ,
               :search,
               %{"query" => "durable event", "namespace" => "global:stolen", "limit" => 3},
               contexts.xerj
             )

    args = search.data["args"]
    assert "project:#{fixture.project.id}:code" in args
    refute "global:stolen" in args
    assert search.data["source"] == "untrusted_retrieval"

    assert {:ok, mcp} =
             Contracts.call(
               "mcp_server",
               McpFilesystemReadonly,
               :configuration,
               %{"tools" => ["read_text_file"]},
               contexts.mcp
             )

    assert mcp.data["package"] == "@modelcontextprotocol/server-filesystem@2026.8.31"
    assert mcp.data["integrity"] =~ "sha512-"
    assert mcp.data["tools_allow"] == ["read_text_file"]
    assert "--offline" in mcp.data["args"]
  end

  test "missing optional binaries degrade plugins without breaking core state", %{
    fixture: fixture,
    contexts: contexts
  } do
    Registry.discover(detection_options(find_executable: fn _name -> nil end))

    for key <- ~w(rtk xerj mcp-filesystem-readonly) do
      assert Repo.get_by!(Plugin, key: key).health == "missing"
    end

    assert Repo.get_by!(Plugin, key: "ponytail").health == "available"
    assert Repo.get!(Run, fixture.run.id).id == fixture.run.id

    assert {:error, :invalid_plugin_capability} =
             Contracts.call("shell_filter", RTK, :filter, %{}, contexts.rtk)
  end

  defp enable_reference_plugins(fixture) do
    rtk = enable("rtk", "global", nil, "standard")
    xerj = enable("xerj", "global", nil, "loopback_network")
    mcp = enable("mcp-filesystem-readonly", "global", nil, "standard")
    ponytail = enable("ponytail", "stage", fixture.attempt.id, "standard")

    {:ok, rtk_context} = Capability.issue(rtk.id, fixture.run.id)
    {:ok, xerj_context} = Capability.issue(xerj.id, fixture.run.id)
    {:ok, mcp_context} = Capability.issue(mcp.id, fixture.run.id)

    {:ok, ponytail_context} =
      Capability.issue(ponytail.id, fixture.run.id, stage_id: fixture.attempt.id)

    %{rtk: rtk_context, xerj: xerj_context, mcp: mcp_context, ponytail: ponytail_context}
  end

  defp enable(key, scope_type, scope_id, approval_kind) do
    plugin = Repo.get_by!(Plugin, key: key)

    assert {:ok, _activation} =
             Registry.enable(plugin.id, scope_type, scope_id, %{
               "permissions" => plugin.manifest_json["permissions"],
               "approval_kind" => approval_kind,
               "actor" => "reference-plugin-test",
               "reason" => "Exercise the reviewed reference plugin",
               "config" => %{}
             })

    plugin
  end

  defp detection_options(overrides \\ []) do
    defaults = [
      bundled_dir: Application.app_dir(:cuckoding, "priv/plugins"),
      user_dir: Path.join(System.tmp_dir!(), "missing-reference-plugin-dir"),
      find_executable: fn
        "rtk" -> "/opt/fake/rtk"
        "xerj" -> "/opt/fake/xerj"
        "npx" -> "/opt/fake/npx"
      end,
      command_runner: fn
        "/opt/fake/rtk", ["--version"], _options -> {"rtk 0.49.0", 0}
        "/opt/fake/xerj", ["--version"], _options -> {"xerj v1.0.0-rc.74", 0}
        "/opt/fake/npx", ["--version"], _options -> {"11.6.2", 0}
      end
    ]

    Keyword.merge(defaults, overrides)
  end

  defp domain_fixture do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Reference plugins #{suffix}",
        repo_path: "/tmp/reference-plugins-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/reference-plugin-workspaces-#{suffix}",
        port_range_start: 56_000,
        port_range_end: 56_100
      })

    {:ok, config} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: String.pad_leading(Integer.to_string(suffix, 16), 64, "0"),
        config_json: %{
          "schema_version" => 2,
          "commands" => %{"verify" => ["/usr/bin/true"]},
          "repository" => %{"protected_paths" => []}
        },
        trusted_at: @now
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "reference-plugins",
        version: 1,
        definition_json: %{"stages" => [%{"key" => "implementation", "role" => "implementer"}]},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Reference plugins",
        concurrency_limit: 1
      })

    {:ok, task} =
      Workflows.create_task(%{board_id: board.id, title: "Reference plugins", position: 0})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        workflow_snapshot_json: workflow.definition_json,
        policy_snapshot_id: config.id,
        plugin_snapshot_json: %{},
        branch: "feature/reference-plugins-#{suffix}",
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

    %{project: project, run: run, attempt: attempt}
  end
end
