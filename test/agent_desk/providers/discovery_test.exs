defmodule AgentDesk.Providers.DiscoveryTest do
  use ExUnit.Case, async: false

  alias AgentDesk.Providers.Discovery

  test "finds a relative command on PATH" do
    dir = tmp_bin_dir!()
    name = "cuckoding-probe-bin-#{System.unique_integer([:positive, :monotonic])}"
    path = Path.join(dir, name)
    File.write!(path, "#!/bin/sh\necho ok\n")
    File.chmod!(path, 0o755)
    isolate_path!(dir)

    assert {:ok, found} = Discovery.find_executable(name)
    assert found == path
  end

  test "find_first returns the first executable that exists" do
    dir = tmp_bin_dir!()
    suffix = System.unique_integer([:positive, :monotonic])
    missing = "cuckoding-missing-bin-#{suffix}"
    second = "cuckoding-second-bin-#{suffix}"
    path = Path.join(dir, second)
    File.write!(path, "#!/bin/sh\necho ok\n")
    File.chmod!(path, 0o755)
    isolate_path!(dir)

    assert {:ok, ^path} = Discovery.find_first([missing, second])
    assert {:error, :not_found} = Discovery.find_first([missing])
  end

  defp tmp_bin_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "agentdesk-discovery-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp isolate_path!(dir) do
    previous = System.get_env("PATH")
    System.put_env("PATH", dir)
    on_exit(fn -> restore_path(previous) end)
  end

  defp restore_path(nil), do: System.delete_env("PATH")
  defp restore_path(path), do: System.put_env("PATH", path)
end
