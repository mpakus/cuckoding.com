defmodule Boss.Deliveries.Request do
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}
  schema "delivery_requests" do
    belongs_to :project, Boss.Projects.Project
    belongs_to :task, Boss.Tasks.Task
    belongs_to :spec_revision, Boss.Projects.SpecRevision
    belongs_to :delivery, Boss.Deliveries.Delivery, type: :string
    field :command_id, :string
    field :admitted_version, :integer
    field :check_config, :map
    field :config_hash, :string
    field :reviewer, :string
    field :status, :string, default: "queued"
    field :reason, :string
    timestamps(type: :utc_datetime_usec)
  end
end
