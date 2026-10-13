defmodule Cuckoding.Battles.Battle do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "battles" do
    field :arena_id, :binary_id
    field :tabula_id, :binary_id
    field :fingerprint, :string
    field :snapshot, :map
    field :context, :map, default: %{}
    field :state, :string
    field :stage, :string
    field :current_task_id, :binary_id
    field :turns_used, :integer, default: 0
    field :deadline_at, :utc_datetime_usec
    field :reason, :string
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Cuckoding.Battles.Task do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "battle_tasks" do
    field :battle_id, :binary_id
    field :task_id, :binary_id
    field :position, :integer
    field :snapshot, :map
    field :context, :map, default: %{}
    field :state, :string, default: "pending"
    field :review_round, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Cuckoding.Battles.Attempt do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "battle_attempts" do
    field :battle_id, :binary_id
    field :task_id, :binary_id
    field :stage, :string
    field :role, :string
    field :state, :string
    field :claim_token, :binary_id
    field :request, :map
    field :result, :map, default: %{}
    field :deadline_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
