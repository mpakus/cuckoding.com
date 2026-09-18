defmodule Cuckoding.Repo.Migrations.CreateResourceMetrics do
  use Ecto.Migration

  def change do
    create table(:resource_samples, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_session_id, references(:agent_sessions, type: :binary_id), null: false
      add :process_id, references(:processes, type: :binary_id), null: false

      add :cpu_nanos, :integer,
        null: false,
        check: %{name: "resource_sample_cpu_non_negative", expr: "cpu_nanos >= 0"}

      add :memory_bytes, :integer,
        null: false,
        check: %{name: "resource_sample_memory_non_negative", expr: "memory_bytes >= 0"}

      add :process_count, :integer,
        null: false,
        check: %{name: "resource_sample_process_count_positive", expr: "process_count > 0"}

      add :open_ports_json, :map, null: false, default: []
      add :sampled_at, :utc_datetime_usec, null: false
      add :limits_enforced, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:resource_samples, [:agent_session_id, :sampled_at])
    create index(:resource_samples, [:process_id, :sampled_at])

    create table(:metric_rollups, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scope_type, :string,
        null: false,
        check: %{
          name: "metric_rollup_scope_type_valid",
          expr: "scope_type IN ('agent_session', 'stage_attempt')"
        }

      add :scope_id, :binary_id, null: false

      add :window, :string,
        null: false,
        check: %{name: "metric_rollup_window_valid", expr: "window IN ('minute', 'stage')"}

      add :bucket_start, :utc_datetime_usec, null: false

      add :sample_count, :integer,
        null: false,
        check: %{name: "metric_rollup_sample_count_positive", expr: "sample_count > 0"}

      add :cpu_nanos, :integer,
        null: false,
        check: %{name: "metric_rollup_cpu_non_negative", expr: "cpu_nanos >= 0"}

      add :average_memory_bytes, :integer,
        null: false,
        check: %{
          name: "metric_rollup_average_memory_non_negative",
          expr: "average_memory_bytes >= 0"
        }

      add :maximum_memory_bytes, :integer,
        null: false,
        check: %{
          name: "metric_rollup_maximum_memory_non_negative",
          expr: "maximum_memory_bytes >= 0"
        }

      add :maximum_process_count, :integer,
        null: false,
        check: %{
          name: "metric_rollup_process_count_positive",
          expr: "maximum_process_count > 0"
        }

      add :open_ports_json, :map, null: false, default: []

      add :active_ms, :integer,
        check: %{
          name: "metric_rollup_active_non_negative",
          expr: "active_ms IS NULL OR active_ms >= 0"
        }

      add :wall_ms, :integer,
        check: %{
          name: "metric_rollup_wall_valid",
          expr:
            "wall_ms IS NULL OR (wall_ms >= 0 AND (active_ms IS NULL OR wall_ms >= active_ms))"
        }

      add :limits_enforced, :boolean, null: false, default: false
      add :computed_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:metric_rollups, [:scope_type, :scope_id, :window, :bucket_start])
  end
end
