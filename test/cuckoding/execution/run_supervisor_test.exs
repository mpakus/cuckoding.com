defmodule Cuckoding.Execution.RunSupervisorTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution.Lease
  alias Cuckoding.Execution.Leases
  alias Cuckoding.Execution.RunSupervisor
  alias Cuckoding.Execution.RunSupervisors

  defmodule DurableWorker do
    use GenServer

    alias Cuckoding.Execution.Lease
    alias Cuckoding.Repo

    def start_link(lease_id), do: GenServer.start_link(__MODULE__, lease_id)
    def owner(pid), do: GenServer.call(pid, :owner)
    def replace_owner(pid, owner), do: GenServer.call(pid, {:replace_owner, owner})

    @impl true
    def init(lease_id), do: {:ok, Repo.get!(Lease, lease_id).owner_id}

    @impl true
    def handle_call(:owner, _from, owner), do: {:reply, owner, owner}

    def handle_call({:replace_owner, replacement}, _from, _owner),
      do: {:reply, :ok, replacement}
  end

  test "a crashed run supervisor rebuilds workers from durable inputs" do
    run_id = Ecto.UUID.generate()
    assert {:ok, %Lease{} = lease, _token} = Leases.acquire("run", run_id, "durable-owner", 5_000)

    assert {:ok, supervisor} = RunSupervisors.start_run(run_id, [{DurableWorker, lease.id}])
    on_exit(fn -> RunSupervisors.stop_run(run_id) end)

    worker = only_worker(supervisor)
    assert DurableWorker.owner(worker) == "durable-owner"
    assert :ok = DurableWorker.replace_owner(worker, "in-memory-only")

    Process.exit(supervisor, :kill)

    restarted = eventually(fn -> RunSupervisor.whereis(run_id) end, supervisor)
    restarted_worker = only_worker(restarted)

    assert restarted != supervisor
    assert restarted_worker != worker
    assert DurableWorker.owner(restarted_worker) == "durable-owner"
  end

  defp only_worker(supervisor) do
    [{_id, pid, :worker, _modules}] = Supervisor.which_children(supervisor)
    pid
  end

  defp eventually(callback, previous, attempts \\ 100)

  defp eventually(_callback, _previous, 0), do: flunk("supervisor did not restart")

  defp eventually(callback, previous, attempts) do
    case callback.() do
      pid when is_pid(pid) and pid != previous ->
        pid

      _other ->
        Process.sleep(10)
        eventually(callback, previous, attempts - 1)
    end
  end
end
