defmodule AgentDesk.Providers.DiscoveryTest do
  use ExUnit.Case, async: false

  alias AgentDesk.Providers.Discovery

  test "finds a relative command on PATH" do
    dir = Path.join(System.tmp_dir!(), "agentdesk-bin-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "cuckoding-probe-bin")
    File.write!(path, "#!/bin/sh\necho ok\n")
    File.chmod!(path, 0o755)

    previous = System.get_env("PATH")
    System.put_env("PATH", dir <> ":" <> previous)
    on_exit(fn -> System.put_env("PATH", previous) end)

    assert {:ok, found} = Discovery.find_executable("cuckoding-probe-bin")
    assert found == path
  end
end
