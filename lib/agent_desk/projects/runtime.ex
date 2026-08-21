defmodule AgentDesk.Projects.Runtime do
  @moduledoc """
  One process per open project.

  Owns project-scoped lifecycle so closing a project can stop its sessions and
  release its resources without affecting another project. The internal A2A
  supervisor starts with every runtime.
  """

  use GenServer, restart: :temporary

  defstruct [:project_id, :canonical_path, :started_at]

  @type t :: %__MODULE__{
          project_id: Ecto.UUID.t(),
          canonical_path: String.t(),
          started_at: DateTime.t()
        }

  @spec start_link(AgentDesk.Projects.Project.t()) :: GenServer.on_start()
  def start_link(project) do
    GenServer.start_link(__MODULE__, project, name: via(project.id))
  end

  @spec via(Ecto.UUID.t()) :: {:via, module(), {module(), Ecto.UUID.t()}}
  def via(project_id) when is_binary(project_id) do
    {:via, Registry, {AgentDesk.ProjectRegistry, project_id}}
  end

  @spec fetch(Ecto.UUID.t()) :: {:ok, pid()} | {:error, :not_started}
  def fetch(project_id) when is_binary(project_id) do
    case Registry.lookup(AgentDesk.ProjectRegistry, project_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_started}
    end
  end

  @spec info(pid() | Ecto.UUID.t()) :: t()
  def info(pid) when is_pid(pid), do: GenServer.call(pid, :info)

  def info(project_id) when is_binary(project_id) do
    GenServer.call(via(project_id), :info)
  end

  @impl true
  def init(project) do
    state = %__MODULE__{
      project_id: project.id,
      canonical_path: project.canonical_path,
      started_at: AgentDesk.Clock.utc_now()
    }

    AgentDesk.Agents.interrupt_orphans(project.id)
    Process.flag(:trap_exit, true)
    {:ok, _pid} = AgentDesk.A2A.Supervisor.start_link(project)
    {:ok, _pid} = AgentDesk.Worktrees.Supervisor.start_link(project)

    {:ok, state}
  end

  @impl true
  def handle_call(:info, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    case Registry.lookup(AgentDesk.A2ASupervisorRegistry, state.project_id) do
      [{pid, _}] -> Supervisor.stop(pid, :shutdown, 2_000)
      [] -> :ok
    end

    case Registry.lookup(AgentDesk.WorktreeSupervisorRegistry, state.project_id) do
      [{pid, _}] -> Supervisor.stop(pid, :shutdown, 2_000)
      [] -> :ok
    end

    :ok
  end
end
