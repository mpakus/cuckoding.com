defmodule Cuckoding.Execution.CommandRecovery do
  @moduledoc """
  Performs one durable command recovery pass after the repository starts.
  """

  use Task

  require Logger

  alias Cuckoding.Execution.CommandDispatcher
  alias Cuckoding.Execution.UnconfiguredCommandHandler

  def start_link(_options), do: Task.start_link(&run/0)

  def run do
    case CommandDispatcher.configured_handler() do
      UnconfiguredCommandHandler ->
        :skipped

      handler ->
        {recovered, nil} = CommandDispatcher.recover_interrupted()
        results = CommandDispatcher.dispatch_due(handler: handler)

        Logger.info("durable command recovery completed",
          recovered_commands: recovered,
          dispatched_commands: length(results)
        )

        {:ok, recovered, results}
    end
  end
end
