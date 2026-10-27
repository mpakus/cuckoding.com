defmodule Boss.Deliveries.Delivery do
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}
  schema "deliveries" do
    belongs_to :project, Boss.Projects.Project
    belongs_to :task, Boss.Tasks.Task
    belongs_to :spec_revision, Boss.Projects.SpecRevision
    field :command_id, :string
    field :reviewer, :string, default: "codex"
    field :admitted_version, :integer
    field :task_version, :integer
    field :check_config, :map
    field :config_hash, :string
    field :status, :string, default: "planning"
    field :cycle, :integer, default: 0
    field :cleanup, :string, default: "pending"
    field :intent, :map, default: %{}
    field :integration_intent, :map, default: %{}
    field :integration_command_id, :string
    field :reason, :string
    has_many :steps, Boss.Deliveries.Step
    timestamps(type: :utc_datetime_usec)
  end
end
