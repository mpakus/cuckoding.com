defmodule AgentDesk.Projects.Supervisor do
  @moduledoc """
  Dynamic supervisor for per-project runtimes.
  """

  use DynamicSupervisor

  alias AgentDesk.Projects.Runtime

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_runtime(AgentDesk.Projects.Project.t()) :: {:ok, pid()} | {:error, term()}
  def start_runtime(project) do
    spec = {Runtime, project}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} -> {:ok, pid}
      {:ok, pid, _info} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop_runtime(Ecto.UUID.t()) :: :ok
  def stop_runtime(project_id) when is_binary(project_id) do
    case Runtime.fetch(project_id) do
      {:ok, pid} ->
        _ = DynamicSupervisor.terminate_child(__MODULE__, pid)
        :ok

      {:error, :not_started} ->
        :ok
    end
  end
end
