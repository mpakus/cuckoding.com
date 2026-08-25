defmodule AgentDesk.Providers.ProcessTest do
  use ExUnit.Case, async: true

  test "wrapper execs through an Erlang port even if setsid returns EPERM" do
    perl = System.find_executable("perl")
    echo = System.find_executable("echo")
    wrapper = Application.app_dir(:agent_desk, "priv/provider_process_wrapper.pl")

    stderr_path =
      Path.join(System.tmp_dir!(), "agentdesk-wrapper-#{System.unique_integer([:positive])}.log")

    on_exit(fn -> File.rm(stderr_path) end)

    assert perl && echo && File.regular?(wrapper)

    port =
      Port.open({:spawn_executable, perl}, [
        :binary,
        :exit_status,
        :use_stdio,
        {:args, [wrapper, stderr_path, echo, "wrapper-ok"]}
      ])

    assert {output, 0} = collect_port_output(port, "")
    assert output =~ "wrapper-ok"
    assert File.read!(stderr_path) == ""
  end

  defp collect_port_output(port, output) do
    receive do
      {^port, {:data, data}} -> collect_port_output(port, output <> data)
      {^port, {:exit_status, status}} -> {output, status}
    after
      2_000 ->
        Port.close(port)
        flunk("timed out waiting for provider process wrapper")
    end
  end
end
