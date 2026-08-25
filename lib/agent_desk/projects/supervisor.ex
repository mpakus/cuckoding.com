defmodule AgentDesk.Projects.Supervisor do
  @moduledoc """
  Supervision boundary for per-project runtimes.

  Each project runs in a temporary slot. The runtime inside the slot is
  permanent, so crashes restart and reconcile that project, while exhausting
  the slot's restart budget cannot take down runtimes for other projects.
  """

  use Supervisor

  alias AgentDesk.Projects.Project
  alias AgentDesk.Projects.Supervisor.Manager

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      AgentDesk.Projects.Supervisor.RuntimePool,
      Manager,
      AgentDesk.Projects.Restorer
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @spec start_runtime(Project.t()) :: {:ok, pid()} | {:error, term()}
  def start_runtime(%Project{} = project) do
    case call_manager({:start_runtime, project}) do
      {:ok, pid, :fresh} ->
        _ = AgentDesk.Reconcile.project(project)
        {:ok, pid}

      {:ok, pid, :existing} ->
        {:ok, pid}

      other ->
        other
    end
  end

  @spec stop_runtime(Ecto.UUID.t()) :: :ok | {:error, term()}
  def stop_runtime(project_id) when is_binary(project_id) do
    call_manager({:stop_runtime, project_id})
  end

  @doc false
  @spec runtime_slots() :: [pid()]
  def runtime_slots do
    AgentDesk.Projects.Supervisor.RuntimePool
    |> DynamicSupervisor.which_children()
    |> Enum.flat_map(fn
      {_id, pid, _type, _modules} when is_pid(pid) -> [pid]
      _other -> []
    end)
  end

  defp call_manager(message) do
    GenServer.call(Manager, message, 15_000)
  catch
    :exit, reason -> {:error, {:project_supervisor_unavailable, reason}}
  end
end

defmodule AgentDesk.Projects.Supervisor.RuntimePool do
  @moduledoc false

  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end

defmodule AgentDesk.Projects.Supervisor.Manager do
  @moduledoc false

  use GenServer

  alias AgentDesk.Projects.Project
  alias AgentDesk.Projects.Runtime
  alias AgentDesk.Projects.Runtime.Slot
  alias AgentDesk.Projects.Supervisor.RuntimePool

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    _ = Runtime.Reconciler.ensure_table()
    {:ok, nil}
  end

  @impl true
  def handle_call({:start_runtime, %Project{} = project}, _from, state) do
    result =
      case DynamicSupervisor.start_child(RuntimePool, {Slot, project}) do
        {:ok, _slot} -> fetch_started(project.id, :fresh)
        {:ok, _slot, _info} -> fetch_started(project.id, :fresh)
        {:error, {:already_started, _slot}} -> fetch_started(project.id, :existing)
        {:error, reason} -> {:error, reason}
      end

    {:reply, result, state}
  end

  def handle_call({:stop_runtime, project_id}, _from, state) do
    result =
      case Slot.fetch(project_id) do
        {:ok, slot} ->
          case DynamicSupervisor.terminate_child(RuntimePool, slot) do
            :ok -> :ok
            {:error, :not_found} -> :ok
            {:error, reason} -> {:error, reason}
          end

        {:error, :not_started} ->
          :ok
      end

    _ = Runtime.Reconciler.forget(project_id)
    {:reply, result, state}
  end

  defp fetch_started(project_id, kind) do
    case Runtime.fetch(project_id) do
      {:ok, pid} -> {:ok, pid, kind}
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule AgentDesk.Projects.Restorer do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @spec await() :: :ok
  def await do
    GenServer.call(__MODULE__, :await, 15_000)
  end

  @impl true
  def init(_opts) do
    :ok = AgentDesk.Projects.restore_on_boot()
    {:ok, nil}
  end

  @impl true
  def handle_call(:await, _from, state) do
    {:reply, :ok, state}
  end
end
