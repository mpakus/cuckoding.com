defmodule AgentDesk.A2A.Context do
  @moduledoc """
  Groups related tasks, messages, delegations, and artifacts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.Agents.Session
  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @statuses ~w(active completed cancelled archived)
  @created_by_types ~w(user agent system)

  schema "a2a_contexts" do
    field :title, :string
    field :status, :string, default: "active"
    field :created_by_type, :string, default: "user"
    field :metadata, :map, default: %{}

    belongs_to :project, Project
    belongs_to :created_by_agent, Session, foreign_key: :created_by_agent_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(context, attrs) do
    context
    |> cast(attrs, [
      :id,
      :project_id,
      :title,
      :status,
      :created_by_type,
      :created_by_agent_id,
      :metadata
    ])
    |> validate_required([:project_id, :title, :status, :created_by_type])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:created_by_type, @created_by_types)
    |> validate_length(:title, max: 200)
    |> foreign_key_constraint(:project_id)
  end
end
