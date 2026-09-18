defmodule Cuckoding.Plugins.SupervisorTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Plugins.Host
  alias Cuckoding.Plugins.Plugin
  alias Cuckoding.Plugins.Registry

  defmodule CrashWorker do
    use GenServer

    def start_link(owner), do: GenServer.start_link(__MODULE__, owner)

    @impl true
    def init(owner) do
      send(owner, :plugin_started)
      Process.send_after(self(), :crash, 5)
      {:ok, nil}
    end

    @impl true
    def handle_info(:crash, state), do: raise("fixture crash, state=#{inspect(state)}")
  end

  test "restart exhaustion degrades only the plugin host" do
    Registry.discover(
      bundled_dir: Path.expand("../../fixtures/plugins", __DIR__),
      user_dir: Path.join(System.tmp_dir!(), "missing-plugin-dir"),
      find_executable: fn
        "fake-tool" -> "/opt/fake-tool"
        _name -> nil
      end,
      command_runner: fn _path, _args, _options -> {"fake-tool 1.4.0", 0} end
    )

    plugin = Repo.get_by!(Plugin, key: "valid-shell")
    core = Process.whereis(Cuckoding.Supervisor)

    host =
      start_supervised!(
        {Host,
         plugin_id: plugin.id, child_spec: {CrashWorker, self()}, max_restarts: 1, max_seconds: 1}
      )

    assert_receive :plugin_started
    assert_receive :plugin_started
    assert eventually(fn -> Host.status(host) == :degraded end)
    assert Repo.get!(Plugin, plugin.id).health == "unhealthy"
    assert Process.alive?(core)
    assert Process.alive?(host)
  end

  defp eventually(check, attempts \\ 50)
  defp eventually(check, 0), do: check.()

  defp eventually(check, attempts) do
    if check.() do
      true
    else
      Process.sleep(10)
      eventually(check, attempts - 1)
    end
  end
end
