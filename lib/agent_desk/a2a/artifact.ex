defmodule AgentDesk.A2A.Artifact do
  @moduledoc """
  Immutable artifact metadata. Bytes live outside hot relational rows.
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

  @kinds ~w(handoff commit patch plan report test_result review transcript diagnostic file other)
  @states ~w(available missing corrupt quarantined)

  schema "artifacts" do
    field :kind, :string
    field :name, :string
    field :mime_type, :string
    field :path, :string
    field :sha256, :string
    field :size_bytes, :integer
    field :state, :string, default: "available"
    field :metadata, :map, default: %{}

    belongs_to :project, Project
    belongs_to :context, Context
    belongs_to :task, Task
    belongs_to :agent_session, Session
    belongs_to :revision_of, __MODULE__

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :id,
      :project_id,
      :context_id,
      :task_id,
      :agent_session_id,
      :kind,
      :name,
      :mime_type,
      :path,
      :sha256,
      :size_bytes,
      :state,
      :revision_of_id,
      :metadata
    ])
    |> validate_required([
      :project_id,
      :context_id,
      :kind,
      :name,
      :mime_type,
      :path,
      :sha256,
      :size_bytes,
      :state
    ])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:state, @states)
    |> validate_number(:size_bytes, greater_than_or_equal_to: 0)
    |> validate_format(:sha256, ~r/^[0-9a-f]{64}$/)
    |> validate_length(:name, max: 200)
    |> validate_no_remote_path()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:context_id)
  end

  defp validate_no_remote_path(changeset) do
    validate_change(changeset, :path, fn :path, path ->
      if String.match?(path, ~r{^[a-zA-Z][a-zA-Z0-9+.-]*://}) do
        [path: "must be a local app-managed or project-relative path"]
      else
        []
      end
    end)
  end
end
