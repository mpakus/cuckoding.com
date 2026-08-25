defmodule AgentDesk.Providers.CommandSpec do
  @moduledoc """
  Executable plus argument array for a provider process. Never a shell string.
  """

  @enforce_keys [:executable]
  @derive {Inspect, except: [:env]}
  defstruct [:executable, args: [], cwd: ".", env: %{}, env_passthrough: []]

  @type t :: %__MODULE__{
          executable: String.t(),
          args: [String.t()],
          cwd: String.t(),
          env: %{optional(String.t()) => String.t()},
          env_passthrough: [String.t()]
        }
end
