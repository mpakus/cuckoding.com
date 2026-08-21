defmodule AgentDesk.Correlation do
  @moduledoc """
  Shared tracing fields for events, messages, and A2A mutations.

  `correlation_id` stays stable across a workflow. `causation_id` points at the
  record that triggered the next write. `context_id` scopes work to an A2A
  context when one exists.
  """

  @enforce_keys [:correlation_id]
  defstruct [:context_id, :correlation_id, :causation_id, :idempotency_key]

  @type t :: %__MODULE__{
          context_id: Ecto.UUID.t() | nil,
          correlation_id: Ecto.UUID.t(),
          causation_id: Ecto.UUID.t() | nil,
          idempotency_key: String.t() | nil
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      context_id: Keyword.get(opts, :context_id),
      correlation_id: Keyword.get(opts, :correlation_id) || AgentDesk.Ids.generate(),
      causation_id: Keyword.get(opts, :causation_id),
      idempotency_key: Keyword.get(opts, :idempotency_key)
    }
  end

  @spec follow(t(), Ecto.UUID.t() | nil) :: t()
  def follow(%__MODULE__{} = parent, caused_by_id) do
    %__MODULE__{
      context_id: parent.context_id,
      correlation_id: parent.correlation_id,
      causation_id: caused_by_id,
      idempotency_key: nil
    }
  end

  @spec to_event_attrs(t()) :: map()
  def to_event_attrs(%__MODULE__{} = correlation) do
    %{
      context_id: correlation.context_id,
      correlation_id: correlation.correlation_id,
      causation_id: correlation.causation_id,
      idempotency_key: correlation.idempotency_key
    }
  end
end
