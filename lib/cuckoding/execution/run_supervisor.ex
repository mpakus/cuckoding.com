defmodule Cuckoding.Execution.RunSupervisors do
  @moduledoc """
  Starts one registered supervisor tree per active run.
  """

  use DynamicSupervisor

  alias Cuckoding.Execution.RunSupervisor

  def start_link(options), do: DynamicSupervisor.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(_options), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_run(run_id, child_specs \\ []) when is_binary(run_id) and is_list(child_specs) do
    DynamicSupervisor.start_child(__MODULE__, {RunSupervisor, {run_id, child_specs}})
  end

  def stop_run(run_id) do
    case RunSupervisor.whereis(run_id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end
end

defmodule Cuckoding.Execution.RunSupervisor do
  @moduledoc """
  Supervises the workers for one run under a unique registry key.
  """

  use Supervisor

  def start_link({run_id, child_specs}) do
    Supervisor.start_link(__MODULE__, child_specs, name: via(run_id))
  end

  def child_spec({run_id, child_specs}) do
    %{
      id: {__MODULE__, run_id},
      start: {__MODULE__, :start_link, [{run_id, child_specs}]},
      restart: :permanent,
      type: :supervisor
    }
  end

  @impl true
  def init(child_specs), do: Supervisor.init(child_specs, strategy: :one_for_one)

  def whereis(run_id) do
    case Registry.lookup(Cuckoding.RunRegistry, run_id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  defp via(run_id), do: {:via, Registry, {Cuckoding.RunRegistry, run_id}}
end
