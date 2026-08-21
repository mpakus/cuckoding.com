defmodule AgentDesk.A2A.Delegation do
  @moduledoc """
  Assignment proposal. Acceptance is the only path that assigns a task.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.A2A.Context
  alias AgentDesk.A2A.Message
  alias AgentDesk.A2A.Task
  alias AgentDesk.Agents.Session
  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @statuses ~w(proposed accepted rejected expired revoked)

  schema "task_delegations" do
    field :status, :string, default: "proposed"
    field :reason, :string
    field :response_reason, :string
    field :idempotency_key, :string
    field :lock_version, :integer, default: 1
    field :expires_at, :utc_datetime_usec
    field :responded_at, :utc_datetime_usec

    belongs_to :project, Project
    belongs_to :context, Context
    belongs_to :task, Task
    belongs_to :from_agent, Session, foreign_key: :from_agent_id
    belongs_to :to_agent, Session, foreign_key: :to_agent_id
    belongs_to :request_message, Message
    belongs_to :response_message, Message

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(delegation, attrs) do
    delegation
    |> cast(attrs, [
      :id,
      :project_id,
      :context_id,
      :task_id,
      :from_agent_id,
      :to_agent_id,
      :status,
      :reason,
      :response_reason,
      :request_message_id,
      :response_message_id,
      :idempotency_key,
      :lock_version,
      :expires_at,
      :responded_at
    ])
    |> validate_required([
      :project_id,
      :context_id,
      :task_id,
      :to_agent_id,
      :status,
      :reason,
      :idempotency_key,
      :lock_version
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:reason, max: 2000)
    |> validate_length(:response_reason, max: 2000)
    |> unique_constraint([:from_agent_id, :idempotency_key],
      name: :task_delegations_idempotency_index
    )
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:to_agent_id)
  end
end
