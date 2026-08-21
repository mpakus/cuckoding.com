defmodule AgentDesk.Resources.Lease do
  @moduledoc """
  Time-limited claim on a file or named resource.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.Agents.Session
  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @types ~w(file directory database migration service port git_ref custom)
  @modes ~w(shared exclusive)
  @statuses ~w(active released expired revoked)

  schema "resource_leases" do
    field :resource_type, :string
    field :resource_key, :string
    field :mode, :string
    field :status, :string, default: "active"
    field :reason, :string
    field :acquired_at, :utc_datetime_usec
    field :renewed_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :released_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :project, Project
    belongs_to :agent_session, Session

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(lease, attrs) do
    lease
    |> cast(attrs, [
      :id,
      :project_id,
      :agent_session_id,
      :resource_type,
      :resource_key,
      :mode,
      :status,
      :reason,
      :acquired_at,
      :renewed_at,
      :expires_at,
      :released_at,
      :metadata
    ])
    |> validate_required([
      :project_id,
      :agent_session_id,
      :resource_type,
      :resource_key,
      :mode,
      :status,
      :reason,
      :acquired_at,
      :renewed_at,
      :expires_at
    ])
    |> validate_inclusion(:resource_type, @types)
    |> validate_inclusion(:mode, @modes)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:reason, max: 500)
    |> validate_length(:resource_key, max: 1000)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:agent_session_id)
  end
end
