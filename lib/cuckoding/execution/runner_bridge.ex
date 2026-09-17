defmodule Cuckoding.Execution.RunnerBridge do
  @moduledoc "Execution-location boundary for run processes."

  @callback prepare(struct(), keyword()) :: {:ok, struct()} | {:error, term()}
  @callback start(struct(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback exec(struct(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback inspect(struct(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback stream_events(struct(), keyword()) :: {:ok, list()} | {:error, term()}
  @callback destroy(struct(), keyword()) :: :ok | {:error, term()}
end

defmodule Cuckoding.Execution.FakeRunner do
  @moduledoc false
  @behaviour Cuckoding.Execution.RunnerBridge

  @impl true
  def prepare(subject, options), do: result(:prepare, subject, options)
  @impl true
  def start(subject, _command, options), do: result(:start, subject, options)
  @impl true
  def exec(subject, _command, options), do: result(:exec, subject, options)
  @impl true
  def inspect(subject, options), do: result(:inspect, subject, options)
  @impl true
  def stream_events(subject, options), do: result(:stream_events, subject, options)
  @impl true
  def destroy(_subject, options), do: Keyword.get(options, :destroy, :ok)

  defp result(operation, subject, options),
    do: Keyword.get(options, operation, {:ok, subject})
end
