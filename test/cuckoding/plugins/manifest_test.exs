defmodule Cuckoding.Plugins.ManifestTest do
  use ExUnit.Case, async: true

  alias Cuckoding.Plugins.Manifest

  test "loads the valid fixture and rejects an over-permissive path" do
    assert {:ok, manifest} = Manifest.load(fixture("valid"), "bundled")
    assert manifest.data["key"] == "valid-shell"
    assert manifest.data["permissions"]["network"] == "external"

    assert {:error, :over_permissive_path} =
             Manifest.load(fixture("over-permissive"), "user")
  end

  test "rejects arbitrary version commands and duplicate security fields" do
    valid = File.read!(fixture("valid"))
    unsafe = String.replace(valid, "[fake-tool, --version]", "[fake-tool, install]")
    duplicate = valid <> "\npermissions:\n  network: none\n"
    unknown_network = String.replace(valid, "network: external", "network: internet")

    assert {:error, :unsafe_version_command} = load_text(unsafe)
    assert {:error, :duplicate_manifest_field} = load_text(duplicate)
    assert {:error, :invalid_plugin_permissions} = load_text(unknown_network)
  end

  test "detection paths stay inside their plugin directory" do
    valid = File.read!(fixture("valid"))
    unsafe = String.replace(valid, "paths: []", "paths: [../outside]")

    assert {:error, :invalid_detection_paths} = load_text(unsafe)
  end

  defp fixture(name), do: Path.expand("../../fixtures/plugins/#{name}/plugin.yml", __DIR__)

  defp load_text(text) do
    path = Path.join(System.tmp_dir!(), "plugin-#{System.unique_integer([:positive])}.yml")
    File.write!(path, text)
    on_exit(fn -> File.rm(path) end)
    Manifest.load(path, "user")
  end
end
