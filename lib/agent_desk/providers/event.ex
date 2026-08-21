defmodule AgentDesk.Providers.Event do
  @moduledoc """
  Normalized provider event. Type atoms come from a whitelist, never `String.to_atom/1`.
  """

  @types %{
    "session_ready" => :session_ready,
    "turn_started" => :turn_started,
    "message_delta" => :message_delta,
    "message_completed" => :message_completed,
    "reasoning_delta" => :reasoning_delta,
    "command_started" => :command_started,
    "command_output" => :command_output,
    "command_completed" => :command_completed,
    "file_change" => :file_change,
    "tool_started" => :tool_started,
    "tool_completed" => :tool_completed,
    "approval_requested" => :approval_requested,
    "usage" => :usage,
    "turn_completed" => :turn_completed,
    "provider_error" => :provider_error,
    "session_exited" => :session_exited,
    "initialize_result" => :initialize_result,
    "stderr" => :stderr
  }

  @enforce_keys [:type, :payload]
  defstruct [:type, :payload, :provider, :occurred_at]

  @type type ::
          :session_ready
          | :turn_started
          | :message_delta
          | :message_completed
          | :reasoning_delta
          | :command_started
          | :command_output
          | :command_completed
          | :file_change
          | :tool_started
          | :tool_completed
          | :approval_requested
          | :usage
          | :turn_completed
          | :provider_error
          | :session_exited
          | :initialize_result
          | :stderr

  @type t :: %__MODULE__{
          type: type(),
          payload: map(),
          provider: String.t() | nil,
          occurred_at: DateTime.t() | nil
        }

  @spec type_from_string(String.t()) :: {:ok, type()} | :error
  def type_from_string(name) when is_binary(name) do
    Map.fetch(@types, name)
  end

  @spec new(type(), map(), String.t() | nil) :: t()
  def new(type, payload, provider \\ nil) when is_atom(type) and is_map(payload) do
    %__MODULE__{
      type: type,
      payload: payload,
      provider: provider,
      occurred_at: AgentDesk.Clock.utc_now()
    }
  end
end
