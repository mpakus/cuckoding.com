defmodule AgentDesk.Reviews.Item do
  @moduledoc """
  One handoff waiting for review or explicit integration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.A2A.Artifact
  alias AgentDesk.Agents.Session
  alias AgentDesk.Projects.Project
  alias AgentDesk.Worktrees.Worktree

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @statuses ~w(queued accepted rejected merged)
  @policy_statuses ~w(passed failed)

  schema "merge_queue_items" do
    field :branch_name, :string
    field :commit_sha, :string
    field :target_ref, :string
    field :summary, :string
    field :status, :string, default: "queued"
    field :policy_status, :string
    field :policy_report, :map, default: %{}
    field :accepted_by_id, :binary_id
    field :merged_at, :utc_datetime_usec

    belongs_to :project, Project
    belongs_to :artifact, Artifact
    belongs_to :agent_session, Session
    belongs_to :worktree, Worktree

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :id,
      :project_id,
      :artifact_id,
      :agent_session_id,
      :worktree_id,
      :branch_name,
      :commit_sha,
      :target_ref,
      :summary,
      :status,
      :policy_status,
      :policy_report,
      :accepted_by_id,
      :merged_at
    ])
    |> validate_required([
      :project_id,
      :artifact_id,
      :branch_name,
      :commit_sha,
      :target_ref,
      :summary,
      :status,
      :policy_status
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:policy_status, @policy_statuses)
    |> unique_constraint(:artifact_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:artifact_id)
  end
end
