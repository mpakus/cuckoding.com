defmodule Cuckoding.Adapters.ACP.BridgeTest do
  use ExUnit.Case, async: true
  alias Cuckoding.Adapters.ACP.Bridge

  test "only launches the pinned app-packaged artifact, with no global fallback" do
    root = Path.join(System.tmp_dir!(), "cuckoding-bridge-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    options = [bridge_directory: root]
    assert {:error, :acp_bridge_not_built} = Bridge.executable("codex", options)
    Cuckoding.ACPBridgeFixture.install(root, "codex")
    assert {:ok, path} = Bridge.executable("codex", options)
    File.chmod!(path, 0o777)
    assert {:error, :acp_bridge_unverified} = Bridge.executable("codex", options)
    File.chmod!(path, 0o700)
    File.write!(path, "modified")
    assert {:error, :acp_bridge_unverified} = Bridge.executable("codex", options)
    File.rm!(path)
    File.ln_s!("/usr/bin/true", path)
    assert {:error, :acp_bridge_unverified} = Bridge.executable("codex", options)
  end
end
