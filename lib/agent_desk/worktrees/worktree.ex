defmodule AgentDesk.Worktrees.Worktree do
  @moduledoc """
  App-owned Git worktree bound to an agent session.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.Agents.Session
  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @statuses ~w(creating ready dirty handed_off conflicted stale removing removed)

  schema "worktrees" do
    field :path, :string
    field :branch_name, :string
    field :base_commit, :string
    field :head_commit, :string
    field :status, :string, default: "creating"
    field :app_owned, :boolean, default: true
    field :last_scanned_at, :utc_datetime_usec

    belongs_to :project, Project
    belongs_to :agent_session, Session

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(worktree, attrs) do
    worktree
    |> cast(attrs, [
      :id,
      :project_id,
      :agent_session_id,
      :path,
      :branch_name,
      :base_commit,
      :head_commit,
      :status,
      :app_owned,
      :last_scanned_at
    ])
    |> validate_required([:project_id, :path, :branch_name, :base_commit, :status, :app_owned])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:path)
    |> unique_constraint([:project_id, :branch_name])
    |> foreign_key_constraint(:project_id)
  end
end
