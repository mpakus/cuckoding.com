defmodule AgentDesk.Agents.Session do
  @moduledoc """
  Durable identity for a provider session in one project.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @providers ~w(codex claude cursor opencode fake sdk remote)
  @statuses ~w(queued starting idle working waiting blocked completed failed interrupted terminating terminated)

  schema "agent_sessions" do
    field :provider, :string
    field :display_name, :string
    field :role, :string
    field :status, :string, default: "queued"
    field :provider_session_id, :string
    field :provider_version, :string
    field :process_identity, :map, default: %{}
    field :capability_hash, :string
    field :capability_expires_at, :utc_datetime_usec
    field :last_heartbeat_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :exit_reason, :string
    field :settings, :map, default: %{}

    belongs_to :project, Project

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :id,
      :project_id,
      :provider,
      :display_name,
      :role,
      :status,
      :provider_session_id,
      :provider_version,
      :process_identity,
      :capability_hash,
      :capability_expires_at,
      :last_heartbeat_at,
      :started_at,
      :ended_at,
      :exit_reason,
      :settings
    ])
    |> validate_required([:project_id, :provider, :display_name, :status])
    |> validate_inclusion(:provider, @providers)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:display_name, max: 120)
    |> validate_length(:role, max: 120)
    |> validate_length(:exit_reason, max: 2000)
    |> foreign_key_constraint(:project_id)
  end
end
