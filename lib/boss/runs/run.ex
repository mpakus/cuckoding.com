defmodule Boss.Runs.Run do
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}
  schema "agent_runs" do
    belongs_to :project, Boss.Projects.Project
    belongs_to :task, Boss.Tasks.Task
    belongs_to :spec_revision, Boss.Projects.SpecRevision
    field :admitted_version, :integer
    field :command_id, :string
    field :adapter, :string, default: "codex"
    field :status, :string, default: "preparing"
    field :cleanup, :string, default: "pending"
    field :workspace, :map, default: %{}
    field :summary, :map, default: %{}
    field :reason, :string
    field :os_pid, :integer
    field :exit_kind, :string
    field :exit_code, :integer
    field :signal, :integer
    field :head_commit, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
