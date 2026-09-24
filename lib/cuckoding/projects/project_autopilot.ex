defmodule Cuckoding.Projects.ProjectAutopilot do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:project_id, :binary_id, autogenerate: false}
  schema "project_autopilots" do
    field :state, :string, default: "paused"
    field :max_active_runs, :integer, default: 2
    field :critical_blocker_limit, :integer, default: 1
    field :completion_mode, :string, default: "manual"
    field :last_issue, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :project_id,
      :state,
      :max_active_runs,
      :critical_blocker_limit,
      :completion_mode,
      :last_issue
    ])
    |> validate_required([:project_id, :state, :max_active_runs, :critical_blocker_limit])
    |> validate_inclusion(:state, ~w(paused running attention done))
    |> validate_required([:completion_mode])
    |> validate_inclusion(:completion_mode, ~w(manual local))
    |> validate_number(:max_active_runs, greater_than: 0, less_than_or_equal_to: 32)
    |> validate_number(:critical_blocker_limit, greater_than: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:project_id)
  end
end
