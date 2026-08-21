defmodule AgentDesk.Providers.CommandSpec do
  @moduledoc """
  Executable plus argument array for a provider process. Never a shell string.
  """

  @enforce_keys [:executable]
  defstruct [:executable, args: [], cwd: ".", env: %{}]

  @type t :: %__MODULE__{
          executable: String.t(),
          args: [String.t()],
          cwd: String.t(),
          env: %{optional(String.t()) => String.t()}
        }
end
