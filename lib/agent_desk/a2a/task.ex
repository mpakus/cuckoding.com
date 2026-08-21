defmodule AgentDesk.A2A.Task do
  @moduledoc """
  Provider-neutral collaborative task with optimistic transition versions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.A2A.Context
  alias AgentDesk.Agents.Session
  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @statuses ~w(queued assigned working input_required auth_required blocked review completed failed cancelled rejected)
  @created_by ~w(user agent system)

  schema "tasks" do
    field :title, :string
    field :description, :string, default: ""
    field :status, :string, default: "queued"
    field :status_reason, :string
    field :lock_version, :integer, default: 1
    field :priority, :integer, default: 0
    field :created_by, :string, default: "user"
    field :metadata, :map, default: %{}
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :project, Project
    belongs_to :context, Context
    belongs_to :parent_task, __MODULE__
    belongs_to :assigned_agent, Session, foreign_key: :assigned_agent_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :id,
      :project_id,
      :context_id,
      :parent_task_id,
      :title,
      :description,
      :status,
      :status_reason,
      :lock_version,
      :priority,
      :assigned_agent_id,
      :created_by,
      :metadata,
      :started_at,
      :completed_at
    ])
    |> validate_required([:project_id, :context_id, :title, :status, :created_by, :lock_version])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:created_by, @created_by)
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 10_000)
    |> validate_length(:status_reason, max: 2000)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:context_id)
  end
end
