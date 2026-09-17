defmodule Cuckoding.Execution.CommandHandler do
  @moduledoc """
  Executes one claimed durable command using its stable idempotency key.
  """

  alias Cuckoding.Execution.Command

  @callback execute(Command.t()) :: {:ok, map()} | {:error, term()}
end

defmodule Cuckoding.Execution.UnconfiguredCommandHandler do
  @moduledoc false
  @behaviour Cuckoding.Execution.CommandHandler

  @impl true
  def execute(_command), do: {:error, :command_handler_not_configured}
end
