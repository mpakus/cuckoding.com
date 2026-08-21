defmodule AgentDesk.Circuit do
  @moduledoc """
  Bounded crash-loop backoff for providers and XERJ.
  """

  use GenServer

  alias AgentDesk.Clock

  @max_failures 5
  @open_ms 30_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @spec allow?(String.t()) :: boolean()
  def allow?(name) when is_binary(name), do: GenServer.call(__MODULE__, {:allow, name})

  @spec success(String.t()) :: :ok
  def success(name) when is_binary(name), do: GenServer.call(__MODULE__, {:success, name})

  @spec failure(String.t()) :: :ok
  def failure(name) when is_binary(name), do: GenServer.call(__MODULE__, {:failure, name})

  @spec reset(String.t()) :: :ok
  def reset(name) when is_binary(name), do: GenServer.call(__MODULE__, {:reset, name})

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:allow, name}, _from, state) do
    {:reply, permitted?(Map.get(state, name)), state}
  end

  def handle_call({:success, name}, _from, state), do: {:reply, :ok, Map.delete(state, name)}

  def handle_call({:reset, name}, _from, state), do: {:reply, :ok, Map.delete(state, name)}

  def handle_call({:failure, name}, _from, state) do
    now = Clock.utc_now()
    current = Map.get(state, name, %{failures: 0, open_until: nil})
    failures = current.failures + 1
    open_until = if failures >= @max_failures, do: DateTime.add(now, @open_ms, :millisecond)
    {:reply, :ok, Map.put(state, name, %{failures: failures, open_until: open_until})}
  end

  defp permitted?(nil), do: true
  defp permitted?(%{open_until: nil}), do: true

  defp permitted?(%{open_until: until}) do
    DateTime.compare(Clock.utc_now(), until) != :lt
  end
end
