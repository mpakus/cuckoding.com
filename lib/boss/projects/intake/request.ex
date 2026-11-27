defmodule Boss.Projects.Intake.Request do
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}

  schema "project_intakes" do
    belongs_to :project, Boss.Projects.Project
    field :command_id, :string
    field :replan_source_id, :string, virtual: true
    field :brief_task, :map, virtual: true
    field :start_policy, :map, load_in_query: false, writable: :insert
    field :check_text, :string
    field :check_config, :map
    field :config_hash, :string
    field :reviewer, :string
    field :autonomy_version, :integer, default: 0
    field :routing_version, :integer, default: 1
    field :peer_review_version, :integer, load_in_query: false, writable: :insert
    field :planning_version, :integer, default: 0
    field :accepted_attempt_id, :string
    field :model_catalog, :map, default: %{}
    field :workspace, :map, default: %{}
    field :status, :string, default: "planning"
    field :cleanup, :string, default: "pending"
    field :reason, :string
    field :batch_id, :string
    field :stop_requested, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end
end
