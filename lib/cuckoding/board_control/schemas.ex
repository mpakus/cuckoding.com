defmodule Cuckoding.BoardControl.Execution do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "board_executions" do
    field :board_id, :binary_id
    field :controller_task_id, :binary_id
    field :state, :string, default: "running"
    field :revision, :integer, default: 1
    field :base_sha, :string
    field :head_sha, :string
    field :snapshot_json, :map
    field :current_run_id, :binary_id
    field :current_task_id, :binary_id
    field :phase, :string, default: "decision"
    field :issue, :string
    field :pending_action, :string
    field :control_json, :map, default: %{}
    field :finished_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Cuckoding.BoardControl.Item do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "board_execution_items" do
    field :board_execution_id, :binary_id
    field :task_id, :binary_id
    field :snapshot_json, :map
    field :state, :string, default: "pending"
    field :reason, :string
    field :completed_sha, :string
    timestamps(type: :utc_datetime_usec)
  end
end
