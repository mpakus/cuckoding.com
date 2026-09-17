defmodule Cuckoding.Repo.Migrations.CreatePowerEvents do
  use Ecto.Migration

  def change do
    create table(:power_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :kind, :string,
        null: false,
        check: %{
          name: "power_event_kind_is_valid",
          expr:
            "kind IN ('assertion_on', 'assertion_off', 'sleep_gap', 'wake_reconciled', 'unattended_on', 'unattended_off')"
        }

      add :gap_ms, :integer,
        check: %{name: "power_event_gap_is_valid", expr: "gap_ms IS NULL OR gap_ms > 0"}

      add :affected_runs_json, :map, null: false, default: []
      add :metadata_json, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:power_events, [:occurred_at])
  end
end
