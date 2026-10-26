defmodule Boss.ApplicationTest do
  use ExUnit.Case, async: false

  defmodule SlowChild do
    use GenServer
    def start_link(observer), do: GenServer.start_link(__MODULE__, observer)

    def init(observer) do
      Process.flag(:trap_exit, true)
      {:ok, observer}
    end

    def terminate(_reason, observer) do
      send(observer, {:stopping, self()})

      receive do
        :finish -> :ok
      end
    end
  end

  @tag capture_log: true
  test "ownership remains held until every supervised child has stopped" do
    directory = Application.fetch_env!(:boss, :data_dir)
    {:ok, child} = Supervisor.start_child(Boss.Supervisor, {SlowChild, self()})
    observer = self()

    {:ok, worker} =
      Task.Supervisor.start_child(Boss.SpecImportSupervisor, fn ->
        Process.flag(:trap_exit, true)
        send(observer, :worker_ready)

        receive do
          {:EXIT, _, :shutdown} ->
            send(observer, {:worker_stopped, Process.alive?(Process.whereis(Boss.Repo))})
        end
      end)

    monitor = Process.monitor(worker)
    assert_receive :worker_ready
    stopping = Task.async(fn -> Application.stop(:boss) end)

    assert_receive {:stopping, ^child}, 1000
    assert {:error, reason} = Boss.DataDirectory.acquire(directory)
    assert reason =~ "already in use"
    send(child, :finish)
    assert :ok = Task.await(stopping)
    assert_receive {:worker_stopped, true}
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
    assert {:ok, lock} = Boss.DataDirectory.acquire(directory)
    Boss.DataDirectory.release(lock)
    assert {:ok, _} = Application.ensure_all_started(:boss)
    Ecto.Adapters.SQL.Sandbox.mode(Boss.Repo, :manual)
  end
end
