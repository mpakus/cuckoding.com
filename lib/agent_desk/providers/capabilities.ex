defmodule AgentDesk.Providers.Capabilities do
  @moduledoc """
  Declared adapter capabilities. The UI must not invent controls the adapter
  cannot implement.
  """

  @enforce_keys [:key]
  defstruct key: nil,
            structured_events: false,
            multi_turn: false,
            resume: false,
            steer_active_turn: false,
            approvals: false,
            mcp_stdio: false,
            mcp_http: false,
            file_change_events: false,
            usage_events: false,
            structured_output: false,
            internal_a2a: true,
            safe_boundary_delivery: true

  @type t :: %__MODULE__{
          key: String.t(),
          structured_events: boolean(),
          multi_turn: boolean(),
          resume: boolean(),
          steer_active_turn: boolean(),
          approvals: boolean(),
          mcp_stdio: boolean(),
          mcp_http: boolean(),
          file_change_events: boolean(),
          usage_events: boolean(),
          structured_output: boolean(),
          internal_a2a: boolean(),
          safe_boundary_delivery: boolean()
        }
end
