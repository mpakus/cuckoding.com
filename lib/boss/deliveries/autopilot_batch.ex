defmodule Boss.Deliveries.AutopilotBatch do
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}
  schema "autopilots" do
    belongs_to :project, Boss.Projects.Project
    field :command_id, :string
    field :task_ids, {:array, :integer}
    field :check_config, :map
    field :config_hash, :string
    field :reviewer, :string
    field :status, :string, default: "running"
    field :reason, :string
    field :version, :integer, default: 0
    field :last_action, :string
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Boss.Deliveries.AutopilotItem do
  use Ecto.Schema
  @primary_key {:request_id, :string, autogenerate: false}
  schema "autopilot_items" do
    belongs_to :autopilot, Boss.Deliveries.AutopilotBatch, type: :string
    field :position, :integer
    field :integration_command_id, :string
  end
end
