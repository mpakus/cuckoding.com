defmodule AgentDesk.A2A.Message do
  @moduledoc """
  Durable multipart A2A message. Delivery state lives on `Delivery` rows.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.A2A.Context
  alias AgentDesk.A2A.Task
  alias AgentDesk.Agents.Session
  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @scopes ~w(direct task context project system)
  @kinds ~w(info request response warning handoff coordination)
  @priorities ~w(low normal high urgent)

  schema "messages" do
    field :scope, :string
    field :kind, :string, default: "info"
    field :body, :string
    field :parts, {:array, :map}, default: []
    field :priority, :string, default: "normal"
    field :requires_ack, :boolean, default: true
    field :metadata, :map, default: %{}
    field :idempotency_key, :string
    field :correlation_id, :binary_id
    field :causation_id, :binary_id
    field :expires_at, :utc_datetime_usec

    belongs_to :project, Project
    belongs_to :context, Context
    belongs_to :task, Task
    belongs_to :sender_agent, Session, foreign_key: :sender_agent_id
    belongs_to :recipient_agent, Session, foreign_key: :recipient_agent_id
    belongs_to :reply_to_message, __MODULE__

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :id,
      :project_id,
      :context_id,
      :task_id,
      :sender_agent_id,
      :recipient_agent_id,
      :scope,
      :kind,
      :body,
      :parts,
      :priority,
      :requires_ack,
      :metadata,
      :idempotency_key,
      :correlation_id,
      :causation_id,
      :reply_to_message_id,
      :expires_at
    ])
    |> validate_required([
      :project_id,
      :context_id,
      :scope,
      :kind,
      :parts,
      :priority,
      :idempotency_key,
      :correlation_id
    ])
    |> validate_inclusion(:scope, @scopes)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:priority, @priorities)
    |> validate_length(:body, max: 10_000)
    |> validate_scope_fields()
    |> unique_constraint([:sender_agent_id, :idempotency_key],
      name: :messages_sender_idempotency_index
    )
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:context_id)
  end

  defp validate_scope_fields(changeset) do
    case get_field(changeset, :scope) do
      "direct" -> validate_required(changeset, [:recipient_agent_id])
      "task" -> validate_required(changeset, [:task_id])
      _other -> changeset
    end
  end
end
