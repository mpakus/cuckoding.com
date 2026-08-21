defmodule AgentDesk.Projects.Runtime do
  @moduledoc """
  One process per open project.

  Owns project-scoped lifecycle so closing a project can stop its sessions and
  release its resources without affecting another project. Child supervisors
  for A2A, leases, and worktrees are added in later phases.
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

    {:ok, state}
  end

  @impl true
  def handle_call(:info, _from, state), do: {:reply, state, state}
end
