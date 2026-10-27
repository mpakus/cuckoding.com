defmodule Boss.Tasks.Event do
  use Ecto.Schema

  schema "task_events" do
    belongs_to :task, Boss.Tasks.Task
    belongs_to :spec_revision, Boss.Projects.SpecRevision
    belongs_to :target_spec_revision, Boss.Projects.SpecRevision
    field :command_id, :string
    field :version, :integer
    field :action, :string
    field :from_state, :string
    field :to_state, :string
    field :reason, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
