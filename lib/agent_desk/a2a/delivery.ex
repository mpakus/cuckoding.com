defmodule AgentDesk.A2A.Delivery do
  @moduledoc """
  Per-recipient inbox row. Acknowledgement never mutates the message.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.A2A.Message
  alias AgentDesk.Agents.Session

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @states ~w(pending injected acknowledged expired skipped)

  schema "message_deliveries" do
    field :inbox_sequence, :integer
    field :state, :string, default: "pending"
    field :attempt_count, :integer, default: 0
    field :last_error, :string
    field :injected_at, :utc_datetime_usec
    field :acknowledged_at, :utc_datetime_usec

    belongs_to :message, Message
    belongs_to :agent_session, Session

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :id,
      :message_id,
      :agent_session_id,
      :inbox_sequence,
      :state,
      :attempt_count,
      :last_error,
      :injected_at,
      :acknowledged_at
    ])
    |> validate_required([:message_id, :agent_session_id, :inbox_sequence, :state])
    |> validate_inclusion(:state, @states)
    |> validate_number(:inbox_sequence, greater_than: 0)
    |> unique_constraint([:message_id, :agent_session_id])
    |> unique_constraint([:agent_session_id, :inbox_sequence])
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:agent_session_id)
  end
end
