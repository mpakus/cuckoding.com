defmodule Cuckoding.Repo.Migrations.CreateUsageAccounting do
  use Ecto.Migration

  def change do
    create table(:price_catalog_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string, null: false
      add :version, :integer,
        null: false,
        check: %{name: "price_catalog_version_positive", expr: "version > 0"}

      add :effective_from, :utc_datetime_usec, null: false
      add :source_uri, :text, null: false
      add :catalog_json, :map, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:price_catalog_versions, [:provider, :version])
    create unique_index(:price_catalog_versions, [:provider, :effective_from])

    create table(:usage_records, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :agent_session_id,
          references(:agent_sessions, type: :binary_id, on_delete: :restrict),
          null: false

      add :event_key_hash, :string, null: false
      add :provider, :string, null: false
      add :model, :string

      add :source, :string,
        null: false,
        check: %{
          name: "usage_source_valid",
          expr: "source IN ('provider_reported', 'unavailable')"
        }

      add :confidence, :string,
        null: false,
        check: %{
          name: "usage_confidence_valid",
          expr: "confidence IN ('provider_reported', 'unavailable')"
        }

      add :input_tokens, :integer, check: non_negative_or_null("input_tokens")
      add :output_tokens, :integer, check: non_negative_or_null("output_tokens")
      add :reasoning_tokens, :integer, check: non_negative_or_null("reasoning_tokens")
      add :cache_read_tokens, :integer, check: non_negative_or_null("cache_read_tokens")
      add :cache_write_tokens, :integer, check: non_negative_or_null("cache_write_tokens")

      add :billing_mode, :string,
        null: false,
        check: %{
          name: "usage_billing_mode_valid",
          expr: "billing_mode IN ('api', 'subscription', 'unknown')"
        }

      add :cost_micros, :integer
      add :currency, :string

      add :cost_source, :string,
        null: false,
        check: %{
          name: "usage_cost_source_valid",
          expr: "cost_source IN ('provider_reported', 'catalog_estimate', 'unavailable')"
        }

      add :cost_confidence, :string,
        null: false,
        check: %{
          name: "usage_cost_confidence_valid",
          expr: "cost_confidence IN ('provider_reported', 'catalog_estimate', 'unavailable')"
        }

      add :price_catalog_version_id,
          references(:price_catalog_versions, type: :binary_id, on_delete: :restrict)

      add :formula_json, :map,
        check: %{
          name: "usage_cost_provenance_valid",
          expr: cost_provenance_check()
        }

      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:usage_records, [:agent_session_id, :event_key_hash])
    create index(:usage_records, [:occurred_at])
    create index(:usage_records, [:price_catalog_version_id])

    create table(:optimization_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :restrict), null: false
      add :plugin_key, :string, null: false
      add :kind, :string, null: false
      add :raw_units, :integer,
        null: false,
        check: %{name: "optimization_raw_non_negative", expr: "raw_units >= 0"}

      add :optimized_units, :integer,
        null: false,
        check: %{
          name: "optimization_optimized_valid",
          expr: "optimized_units >= 0 AND optimized_units <= raw_units"
        }

      add :saved_units, :integer,
        null: false,
        check: %{
          name: "optimization_saved_valid",
          expr: "saved_units = raw_units - optimized_units"
        }

      add :source, :string,
        null: false,
        default: "plugin_reported",
        check: %{name: "optimization_source_valid", expr: "source = 'plugin_reported'"}

      add :confidence, :string,
        null: false,
        check: %{
          name: "optimization_confidence_valid",
          expr: "confidence IN ('reported', 'estimated')"
        }

      add :estimation_method, :string, null: false
      add :metadata_json, :map, null: false, default: %{}
      add :recorded_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:optimization_records, [:run_id, :plugin_key, :recorded_at])

    for table <- ~w(price_catalog_versions usage_records optimization_records) do
      execute(
        """
        CREATE TRIGGER #{table}_no_update
        BEFORE UPDATE ON #{table}
        BEGIN
          SELECT RAISE(ABORT, '#{table} are append-only');
        END;
        """,
        "DROP TRIGGER #{table}_no_update"
      )

      execute(
        """
        CREATE TRIGGER #{table}_no_delete
        BEFORE DELETE ON #{table}
        BEGIN
          SELECT RAISE(ABORT, '#{table} are append-only');
        END;
        """,
        "DROP TRIGGER #{table}_no_delete"
      )
    end
  end

  defp non_negative_or_null(column) do
    %{name: "usage_#{column}_non_negative", expr: "#{column} IS NULL OR #{column} >= 0"}
  end

  defp cost_provenance_check do
    "((cost_micros IS NULL AND currency IS NULL) OR " <>
      "(cost_micros >= 0 AND currency IS NOT NULL)) AND (" <>
      "(cost_source = 'provider_reported' AND cost_confidence = 'provider_reported' " <>
      "AND cost_micros IS NOT NULL AND price_catalog_version_id IS NULL AND formula_json IS NULL) OR " <>
      "(cost_source = 'catalog_estimate' AND cost_confidence = 'catalog_estimate' " <>
      "AND billing_mode = 'api' AND cost_micros IS NOT NULL " <>
      "AND price_catalog_version_id IS NOT NULL AND formula_json IS NOT NULL) OR " <>
      "(cost_source = 'unavailable' AND cost_confidence = 'unavailable' " <>
      "AND cost_micros IS NULL AND price_catalog_version_id IS NULL AND formula_json IS NULL))"
  end
end
