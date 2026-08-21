defmodule AgentDesk.A2A.Participant do
  @moduledoc """
  Explicit A2A context membership used for authorization and fan-out.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.A2A.Context
  alias AgentDesk.Agents.Session

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @roles ~w(owner participant reviewer observer)

  schema "a2a_context_participants" do
    field :role, :string
    field :joined_at, :utc_datetime_usec
    field :left_at, :utc_datetime_usec

    belongs_to :context, Context
    belongs_to :agent_session, Session

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:id, :context_id, :agent_session_id, :role, :joined_at, :left_at])
    |> validate_required([:context_id, :agent_session_id, :role, :joined_at])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:context_id, :agent_session_id],
      name: :a2a_context_participants_active_index
    )
    |> foreign_key_constraint(:context_id)
    |> foreign_key_constraint(:agent_session_id)
  end
end
