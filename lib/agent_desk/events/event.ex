defmodule AgentDesk.Events.Event do
  @moduledoc """
  Append-only normalized activity record.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "events" do
    field :type, :string
    field :source, :string
    field :correlation_id, :binary_id
    field :causation_id, :binary_id
    field :idempotency_key, :string
    field :payload, :map, default: %{}
    field :occurred_at, :utc_datetime_usec
    field :agent_session_id, :binary_id
    field :task_id, :binary_id
    field :context_id, :binary_id

    belongs_to :project, AgentDesk.Projects.Project

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required [:project_id, :type, :source, :occurred_at]

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :id,
      :project_id,
      :agent_session_id,
      :task_id,
      :context_id,
      :type,
      :source,
      :correlation_id,
      :causation_id,
      :idempotency_key,
      :payload,
      :occurred_at
    ])
    |> validate_required(@required)
    |> foreign_key_constraint(:project_id)
  end
end
