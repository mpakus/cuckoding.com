defmodule Cuckoding.ExecutionSupervisor do
  @moduledoc "Restart a coordinator and its task supervisor together, after old workers stop."
  use Supervisor

  def start_link(options), do: Supervisor.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: Keyword.fetch!(options, :coordinator),
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor,
      shutdown: :infinity
    }
  end

  @impl true
  def init(options) do
    children = [
      {Task.Supervisor, name: Keyword.fetch!(options, :tasks)},
      {Keyword.fetch!(options, :coordinator), Keyword.get(options, :options, [])}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
