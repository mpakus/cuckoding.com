defmodule Boss.Deliveries.AutopilotLoopConfig do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:autopilot_id, :string, autogenerate: false}

  schema "autopilot_loop_configs" do
    field :project_id, :integer
    field :parallel_enabled, :integer, default: 1
    field :spec_loop_enabled, :integer, default: 1
    field :loop_pass, :integer, default: 1
    field :max_passes, :integer, default: 2
    field :parent_autopilot_id, :string
    field :reworked_task_ids, :string, default: "[]"
    field :next_autopilot_id, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :autopilot_id,
      :project_id,
      :parallel_enabled,
      :spec_loop_enabled,
      :loop_pass,
      :max_passes,
      :parent_autopilot_id,
      :reworked_task_ids,
      :next_autopilot_id
    ])
    |> validate_required([:autopilot_id, :project_id])
  end
end
