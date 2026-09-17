defmodule Cuckoding.Execution.CommandRecovery do
  @moduledoc """
  Performs one durable command recovery pass after the repository starts.
  """

  use Task

  require Logger

  alias Cuckoding.Execution.CommandDispatcher
  alias Cuckoding.Execution.UnconfiguredCommandHandler

  def start_link(_options), do: Task.start_link(&run/0)

  def run(options \\ []) do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())
    {recovered, nil} = recover(now)
    results = dispatch(now: now)

    log(recovered, results)
    {:ok, recovered, results}
  end

  def recover(now \\ Cuckoding.Clock.wall_now()), do: CommandDispatcher.recover_interrupted(now)

  def dispatch(options \\ []) do
    case CommandDispatcher.configured_handler() do
      UnconfiguredCommandHandler -> []
      handler -> CommandDispatcher.dispatch_due(Keyword.put(options, :handler, handler))
    end
  end

  defp log(recovered, results) do
    Logger.info("durable command recovery completed",
      recovered_commands: recovered,
      dispatched_commands: length(results)
    )
  end
end
