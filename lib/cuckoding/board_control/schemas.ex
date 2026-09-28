defmodule Cuckoding.BoardControl.Execution do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "board_executions" do
    field :board_id, :binary_id
    field :controller_task_id, :binary_id
    field :state, :string, default: "running"
    field :mode, :string, default: "fixed_batch"
    field :plan_cycle, :integer, default: 0
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
    field :criteria_json, :map, default: %{}
    field :replacement_ids_json, :map, default: %{}
    field :superseded, :boolean, default: false
    field :retry_count, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Cuckoding.BoardControl.PlanRevision do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "board_plan_revisions" do
    field :board_execution_id, :binary_id
    field :parent_id, :binary_id
    field :run_id, :binary_id
    field :review_run_id, :binary_id
    field :cycle, :integer
    field :state, :string, default: "proposed"
    field :plan_json, :map
    field :baseline_json, :map
    field :review_json, :map
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Cuckoding.BoardControl.Question do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "board_questions" do
    field :board_execution_id, :binary_id
    field :task_id, :binary_id
    field :run_id, :binary_id
    field :revision, :integer
    field :question, :string
    field :answer, :string
    field :answered_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
