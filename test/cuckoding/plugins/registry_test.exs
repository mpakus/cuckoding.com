defmodule Cuckoding.Plugins.RegistryTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.ActivityStream
  alias Cuckoding.Plugins.Activation
  alias Cuckoding.Plugins.Discovery
  alias Cuckoding.Plugins.Plugin
  alias Cuckoding.Plugins.Registry
  alias Cuckoding.Projects

  test "discovers valid manifests without auto-enabling and records missing and wrong versions" do
    result = discover()

    assert Enum.any?(result.errors, &(&1.reason == :over_permissive_path))
    assert Repo.aggregate(Plugin, :count) == 3
    assert Repo.aggregate(Activation, :count) == 0
    assert Repo.get_by!(Plugin, key: "valid-shell").health == "available"
    assert Repo.get_by!(Plugin, key: "missing-tool").health == "missing"
    assert Repo.get_by!(Plugin, key: "wrong-version").health == "version_mismatch"

    user_result =
      Discovery.scan(
        detector_options(
          bundled_dir: Path.join(System.tmp_dir!(), "missing-bundled-plugin-dir"),
          user_dir: fixture_root()
        )
      )

    assert Enum.any?(user_result.manifests, fn {manifest, _detection} ->
             manifest.source == "user" and manifest.data["key"] == "valid-shell"
           end)
  end

  test "network approvals are distinct and child scopes can only narrow permissions" do
    discover()
    plugin = Repo.get_by!(Plugin, key: "valid-shell")
    project = project_fixture()

    external = permissions(plugin, "external")

    assert {:error, :network_approval_mismatch} =
             Registry.enable(plugin.id, "global", nil, attrs(external, "loopback_network"))

    assert {:ok, global} =
             Registry.enable(plugin.id, "global", nil, attrs(external, "external_network"))

    assert global.enabled
    assert global.network == "external"

    events = ActivityStream.list("plugin:#{plugin.id}", 0)
    assert List.last(events).event_type == "plugin.external_enabled"
    assert List.last(events).metadata["permissions_hash"] =~ ~r/^[0-9a-f]{64}$/

    assert {:ok, project_activation} =
             Registry.enable(
               plugin.id,
               "project",
               project.id,
               attrs(permissions(plugin, "loopback"), "loopback_network")
             )

    assert project_activation.network == "loopback"

    expanded =
      plugin
      |> permissions("loopback")
      |> Map.put("write_paths", ["${RUN_WORKTREE}"])

    assert {:error, :permission_expansion} =
             Registry.enable(
               plugin.id,
               "project",
               project.id,
               attrs(expanded, "loopback_network")
             )

    assert {:ok, disabled} =
             Registry.disable(plugin.id, "global", nil, "local-user", "Turn off default")

    refute disabled.enabled

    assert {:error, {:disabled_by_parent_scope, "global"}} =
             Registry.enable(
               plugin.id,
               "project",
               project.id,
               attrs(permissions(plugin, "none"), "standard")
             )
  end

  test "unhealthy detection cannot be enabled" do
    discover()
    plugin = Repo.get_by!(Plugin, key: "missing-tool")
    project = project_fixture()

    assert {:error, :plugin_unavailable} =
             Registry.enable(
               plugin.id,
               "project",
               project.id,
               attrs(plugin.manifest_json["permissions"], "loopback_network")
             )
  end

  defp discover do
    Registry.discover(detector_options())
  end

  defp detector_options(overrides \\ []) do
    defaults = [
      bundled_dir: fixture_root(),
      user_dir: Path.join(System.tmp_dir!(), "missing-plugin-dir"),
      find_executable: fn
        "fake-tool" -> "/opt/fake-tool"
        "old-tool" -> "/opt/old-tool"
        _name -> nil
      end,
      command_runner: fn
        "/opt/fake-tool", ["--version"], _options -> {"fake-tool 1.4.0", 0}
        "/opt/old-tool", ["--version"], _options -> {"old-tool 2.0.0", 0}
      end
    ]

    Keyword.merge(defaults, overrides)
  end

  defp permissions(plugin, network) do
    Map.put(plugin.manifest_json["permissions"], "network", network)
  end

  defp attrs(permissions, approval_kind) do
    %{
      "permissions" => permissions,
      "approval_kind" => approval_kind,
      "actor" => "local-user",
      "reason" => "Reviewed plugin permissions",
      "config" => %{}
    }
  end

  defp project_fixture do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Plugins #{suffix}",
        repo_path: "/tmp/plugin-project-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/plugin-workspace-#{suffix}",
        port_range_start: 54_000,
        port_range_end: 54_100
      })

    project
  end

  defp fixture_root, do: Path.expand("../../fixtures/plugins", __DIR__)
end
