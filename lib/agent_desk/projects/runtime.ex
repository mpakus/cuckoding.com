defmodule AgentDesk.Projects.Runtime do
  @moduledoc """
  One supervisor per open project.

  Owns project-scoped lifecycle so closing a project can stop its sessions and
  release its resources without affecting another project.
  """

  use Supervisor

  defstruct [:project_id, :canonical_path, :started_at]

  @type t :: %__MODULE__{
          project_id: Ecto.UUID.t(),
          canonical_path: String.t(),
          started_at: DateTime.t()
        }

  @spec start_link(AgentDesk.Projects.Project.t()) :: Supervisor.on_start()
  def start_link(project) do
    info = %__MODULE__{
      project_id: project.id,
      canonical_path: project.canonical_path,
      started_at: AgentDesk.Clock.utc_now()
    }

    Supervisor.start_link(__MODULE__, project, name: via(project.id, info))
  end

  @spec via(Ecto.UUID.t()) :: {:via, module(), {module(), Ecto.UUID.t()}}
  def via(project_id) when is_binary(project_id) do
    {:via, Registry, {AgentDesk.ProjectRegistry, project_id}}
  end

  defp via(project_id, info) do
    {:via, Registry, {AgentDesk.ProjectRegistry, project_id, info}}
  end

  @spec fetch(Ecto.UUID.t()) :: {:ok, pid()} | {:error, :not_started}
  def fetch(project_id) when is_binary(project_id) do
    case Registry.lookup(AgentDesk.ProjectRegistry, project_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_started}
    end
  end

  @spec info(pid() | Ecto.UUID.t()) :: t()
  def info(pid) when is_pid(pid) do
    case Registry.keys(AgentDesk.ProjectRegistry, pid) do
      [project_id] -> info(project_id)
      [] -> raise ArgumentError, "project runtime is not registered"
    end
  end

  def info(project_id) when is_binary(project_id) do
    case Registry.lookup(AgentDesk.ProjectRegistry, project_id) do
      [{_pid, %__MODULE__{} = info}] -> info
      [] -> raise ArgumentError, "project runtime is not started"
    end
  end

  @impl true
  def init(project) do
    :ok = await_previous_subtree(project.id)

    children = [
      {__MODULE__.Reconciler, project},
      {AgentDesk.A2A.Supervisor, project},
      {AgentDesk.Providers.ProjectSupervisor, project},
      {AgentDesk.Worktrees.Supervisor, project},
      {AgentDesk.Search.Supervisor, project}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp await_previous_subtree(project_id) do
    [
      AgentDesk.A2ASupervisorRegistry,
      AgentDesk.ProviderSupervisorRegistry,
      AgentDesk.WorktreeSupervisorRegistry,
      AgentDesk.SearchSupervisorRegistry
    ]
    |> Enum.each(&await_registry_release(&1, project_id))

    :ok
  end

  defp await_registry_release(registry, project_id) do
    case Registry.lookup(registry, project_id) do
      [{pid, _value}] ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} ->
            await_registry_release(registry, project_id)
        after
          5_000 ->
            Process.demonitor(ref, [:flush])
            exit({:previous_project_subtree_still_running, registry, project_id})
        end

      [] ->
        :ok
    end
  end
end

defmodule AgentDesk.Projects.Runtime.Slot do
  @moduledoc false

  use Supervisor

  alias AgentDesk.Projects.Project
  alias AgentDesk.Projects.Runtime

  @max_restarts 3
  @max_seconds 5

  @spec child_spec(Project.t()) :: Supervisor.child_spec()
  def child_spec(%Project{} = project) do
    %{
      id: project.id,
      start: {__MODULE__, :start_link, [project]},
      restart: :temporary,
      type: :supervisor,
      shutdown: :infinity
    }
  end

  @spec start_link(Project.t()) :: Supervisor.on_start()
  def start_link(%Project{} = project) do
    Supervisor.start_link(__MODULE__, project, name: via(project.id))
  end

  @spec fetch(Ecto.UUID.t()) :: {:ok, pid()} | {:error, :not_started}
  def fetch(project_id) when is_binary(project_id) do
    case Registry.lookup(AgentDesk.ProjectRegistry, slot_key(project_id)) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_started}
    end
  end

  @impl true
  def init(%Project{} = project) do
    Supervisor.init([{Runtime, project}],
      strategy: :one_for_one,
      max_restarts: @max_restarts,
      max_seconds: @max_seconds
    )
  end

  defp via(project_id) do
    {:via, Registry, {AgentDesk.ProjectRegistry, slot_key(project_id)}}
  end

  defp slot_key(project_id), do: "project-slot:" <> project_id
end

defmodule AgentDesk.Projects.Runtime.Reconciler do
  @moduledoc false

  use GenServer

  alias AgentDesk.Projects.Project

  @table :agent_desk_project_runtime_seen

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, project)
  end

  @spec ensure_table() :: :ok
  def ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        _ = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        :ok

      _tid ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  @spec forget(Ecto.UUID.t()) :: :ok
  def forget(project_id) when is_binary(project_id) do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _tid -> true = :ets.delete(@table, project_id)
    end

    :ok
  end

  @impl true
  def init(%Project{} = project) do
    restart? = seen?(project.id)
    remember(project.id)

    if restart? do
      _ = AgentDesk.Reconcile.project(project)
    end

    {:ok, project}
  end

  defp seen?(project_id) do
    case :ets.whereis(@table) do
      :undefined -> false
      _tid -> :ets.member(@table, project_id)
    end
  end

  defp remember(project_id) do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _tid -> true = :ets.insert(@table, {project_id, true})
    end
  end
end
