defmodule AgentDesk.A2A.IdempotencyRecord do
  @moduledoc """
  Bounded replay result for a mutating A2A operation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.Agents.Session
  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @result_statuses ~w(succeeded failed)

  schema "idempotency_records" do
    field :idempotency_key, :string
    field :operation, :string
    field :request_hash, :string
    field :result_status, :string
    field :result_payload, :map, default: %{}
    field :expires_at, :utc_datetime_usec

    belongs_to :project, Project
    belongs_to :agent_session, Session

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :project_id,
      :agent_session_id,
      :idempotency_key,
      :operation,
      :request_hash,
      :result_status,
      :result_payload,
      :expires_at
    ])
    |> validate_required([
      :project_id,
      :agent_session_id,
      :idempotency_key,
      :operation,
      :request_hash,
      :result_status,
      :expires_at
    ])
    |> validate_inclusion(:result_status, @result_statuses)
    |> unique_constraint([:agent_session_id, :idempotency_key])
    |> foreign_key_constraint(:agent_session_id)
  end
end
