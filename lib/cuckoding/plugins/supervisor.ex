defmodule Cuckoding.Plugins.Supervisor do
  @moduledoc "Starts isolated plugin hosts without making them authoritative for plugin state."

  use DynamicSupervisor

  alias Cuckoding.Plugins.Host

  def start_link(options) do
    DynamicSupervisor.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def init(_options), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_plugin(plugin_id, child_spec, options \\ []) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Host, Keyword.merge(options, plugin_id: plugin_id, child_spec: child_spec)}
    )
  end
end

defmodule Cuckoding.Plugins.Host do
  @moduledoc "Monitors one plugin child and degrades after its restart budget is exhausted."

  use GenServer

  alias Cuckoding.Plugins.Registry

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :plugin_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      type: :worker
    }
  end

  def status(server), do: GenServer.call(server, :status)

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    state = %{
      child: nil,
      child_spec: Supervisor.child_spec(Keyword.fetch!(options, :child_spec), []),
      max_restarts: Keyword.get(options, :max_restarts, 3),
      max_seconds: Keyword.get(options, :max_seconds, 5),
      monitor: nil,
      parent: Keyword.get(options, :parent) || List.first(Process.get(:"$ancestors")),
      plugin_id: Keyword.fetch!(options, :plugin_id),
      restarts: [],
      status: :starting
    }

    {:ok, state, {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, state) do
    case start_child(state) do
      {:ok, state} -> {:noreply, state}
      {:error, reason} -> {:noreply, degrade(state, reason)}
    end
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  @impl true
  def handle_info(
        {:DOWN, monitor, :process, child, reason},
        %{child: child, monitor: monitor} = state
      ) do
    state = %{state | child: nil, monitor: nil}
    now = System.monotonic_time(:millisecond)
    cutoff = now - state.max_seconds * 1_000
    restarts = Enum.filter(state.restarts, &(&1 >= cutoff))

    if length(restarts) < state.max_restarts do
      case start_child(%{state | restarts: [now | restarts]}) do
        {:ok, state} -> {:noreply, state}
        {:error, start_reason} -> {:noreply, degrade(state, {reason, start_reason})}
      end
    else
      {:noreply, degrade(state, reason)}
    end
  end

  def handle_info({:EXIT, parent, reason}, %{parent: parent} = state), do: {:stop, reason, state}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{child: child, monitor: monitor}) when is_pid(child) do
    if is_reference(monitor), do: Process.demonitor(monitor, [:flush])
    if Process.alive?(child), do: Process.exit(child, :shutdown)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp start_child(state) do
    {module, function, arguments} = state.child_spec.start

    case apply(module, function, arguments) do
      {:ok, child} when is_pid(child) ->
        Process.unlink(child)
        {:ok, %{state | child: child, monitor: Process.monitor(child), status: :running}}

      :ignore ->
        {:error, :plugin_child_ignored}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:invalid_plugin_start_result, other}}
    end
  end

  defp degrade(state, reason) do
    error = "plugin restart limit reached: #{inspect(reason, limit: 10, printable_limit: 200)}"
    Registry.mark_unhealthy(state.plugin_id, error)
    %{state | status: :degraded}
  end
end
