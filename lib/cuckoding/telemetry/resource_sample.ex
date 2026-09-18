defmodule Cuckoding.Telemetry.ResourceSample do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "resource_samples" do
    field :agent_session_id, :binary_id
    field :process_id, :binary_id
    field :cpu_nanos, :integer
    field :memory_bytes, :integer
    field :process_count, :integer
    field :open_ports_json, {:array, :integer}, default: []
    field :sampled_at, :utc_datetime_usec
    field :limits_enforced, :boolean, default: false
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(sample, attrs) do
    sample
    |> cast(attrs, [
      :id,
      :agent_session_id,
      :process_id,
      :cpu_nanos,
      :memory_bytes,
      :process_count,
      :open_ports_json,
      :sampled_at,
      :limits_enforced
    ])
    |> validate_required([
      :id,
      :agent_session_id,
      :process_id,
      :cpu_nanos,
      :memory_bytes,
      :process_count,
      :open_ports_json,
      :sampled_at,
      :limits_enforced
    ])
    |> validate_number(:cpu_nanos, greater_than_or_equal_to: 0)
    |> validate_number(:memory_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:process_count, greater_than: 0)
    |> foreign_key_constraint(:agent_session_id)
    |> foreign_key_constraint(:process_id)
  end
end

defmodule Cuckoding.Telemetry.MetricRollup do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "metric_rollups" do
    field :scope_type, :string
    field :scope_id, :binary_id
    field :window, :string
    field :bucket_start, :utc_datetime_usec
    field :sample_count, :integer
    field :cpu_nanos, :integer
    field :average_memory_bytes, :integer
    field :maximum_memory_bytes, :integer
    field :maximum_process_count, :integer
    field :open_ports_json, {:array, :integer}, default: []
    field :active_ms, :integer
    field :wall_ms, :integer
    field :limits_enforced, :boolean, default: false
    field :computed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(rollup, attrs) do
    rollup
    |> cast(attrs, [
      :id,
      :scope_type,
      :scope_id,
      :window,
      :bucket_start,
      :sample_count,
      :cpu_nanos,
      :average_memory_bytes,
      :maximum_memory_bytes,
      :maximum_process_count,
      :open_ports_json,
      :active_ms,
      :wall_ms,
      :limits_enforced,
      :computed_at
    ])
    |> validate_required([
      :id,
      :scope_type,
      :scope_id,
      :window,
      :bucket_start,
      :sample_count,
      :cpu_nanos,
      :average_memory_bytes,
      :maximum_memory_bytes,
      :maximum_process_count,
      :open_ports_json,
      :limits_enforced,
      :computed_at
    ])
    |> validate_inclusion(:scope_type, ~w(agent_session stage_attempt))
    |> validate_inclusion(:window, ~w(minute stage))
    |> validate_number(:sample_count, greater_than: 0)
    |> validate_number(:cpu_nanos, greater_than_or_equal_to: 0)
    |> validate_number(:average_memory_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:maximum_memory_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:maximum_process_count, greater_than: 0)
    |> validate_number(:active_ms, greater_than_or_equal_to: 0)
    |> validate_number(:wall_ms, greater_than_or_equal_to: 0)
    |> validate_wall_time()
    |> unique_constraint([:scope_type, :scope_id, :window, :bucket_start])
  end

  defp validate_wall_time(changeset) do
    active_ms = get_field(changeset, :active_ms)
    wall_ms = get_field(changeset, :wall_ms)

    if is_integer(active_ms) and is_integer(wall_ms) and wall_ms < active_ms,
      do: add_error(changeset, :wall_ms, "must include active time"),
      else: changeset
  end
end
