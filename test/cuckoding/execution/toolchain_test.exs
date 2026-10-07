defmodule Cuckoding.Execution.ToolchainTest do
  use ExUnit.Case, async: true
  alias Cuckoding.Execution.Toolchain

  test "discovers native installations without executing shims or loading personal settings" do
    home = Path.join(System.tmp_dir!(), "toolchain-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(home) end)
    marker = Path.join(home, "executed")
    shim = executable(home, ".volta/bin/node", "touch #{marker}")
    node = executable(home, ".volta/tools/image/node/24.0.0/bin/node", "exit 0")
    npm = executable(home, ".volta/tools/image/node/24.0.0/bin/npm", "exit 0")
    alias_path = Path.join(home, ".local/bin/node")
    File.mkdir_p!(Path.dirname(alias_path))
    File.ln_s!(shim, alias_path)

    catalog = Toolchain.catalog(home: home, path: Path.dirname(shim), system_dirs: [])
    assert catalog["node"] == [node]
    refute File.exists?(marker)
    assert {:ok, ^node} = Toolchain.resolve("node", catalog)
    assert {:error, :goal_toolchain_unavailable} = Toolchain.resolve(shim, catalog)
    assert {:error, :goal_toolchain_unavailable} = Toolchain.resolve(alias_path, catalog)
    assert {:error, :goal_toolchain_unavailable} = Toolchain.resolve("./node", catalog)
    assert {:ok, snapshot} = Toolchain.snapshot([%{"command" => [npm, "test"]}], catalog)
    assert Enum.map(snapshot["tools"], & &1["name"]) == ["node", "npm"]

    assert Toolchain.environment(snapshot) == %{
             "PATH" => Path.dirname(node) <> ":/usr/bin:/bin:/usr/sbin:/sbin"
           }

    assert Cuckoding.Security.Redactor.redact(snapshot) == snapshot
    assert Toolchain.current?(snapshot)
    refute Toolchain.current?(%{"tools" => []})

    other_node = executable(home, ".volta/tools/image/node/22.0.0/bin/node", "exit 0")

    assert {:error, :goal_toolchain_unavailable} =
             Toolchain.snapshot(
               [
                 %{"command" => [node, "--test"]},
                 %{"command" => [other_node, "--test"]}
               ],
               catalog
             )

    File.write!(node, "Changed installation")
    refute Toolchain.current?(snapshot)
  end

  test "runtime companions must be present and metadata-valid" do
    home = Path.join(System.tmp_dir!(), "toolchain-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(home) end)
    mix = executable(home, ".asdf/installs/elixir/1.19.5/bin/mix", "exit 0")
    catalog = Toolchain.catalog(home: home, path: "", system_dirs: [])

    assert {:error, :goal_toolchain_unavailable} =
             Toolchain.snapshot([%{"command" => [mix, "test"]}], catalog)

    File.chmod!(mix, 0o600)
    assert Toolchain.catalog(home: home, path: "", system_dirs: [])["mix"] == []
  end

  defp executable(home, relative, body) do
    path = Path.join(home, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "#!/bin/sh\n#{body}\n")
    File.chmod!(path, 0o700)
    path
  end
end
