defmodule Cuckoding.Repo.Migrations.CreatePlugins do
  use Ecto.Migration

  def change do
    create table(:plugins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :name, :string, null: false
      add :kind, :string,
        null: false,
        check: %{
          name: "plugins_kind_is_valid",
          expr:
            "kind IN ('knowledge_backend', 'shell_filter', 'instruction_skill', " <>
              "'mcp_server', 'runner', 'metric_source', 'vcs_host', 'secret_store', 'notifier')"
        }

      add :version, :string, null: false
      add :source, :string,
        null: false,
        check: %{name: "plugins_source_is_valid", expr: "source IN ('bundled', 'user')"}

      add :manifest_path, :text, null: false
      add :manifest_hash, :string, null: false
      add :manifest_json, :map, null: false
      add :detected_binaries_json, :map, null: false, default: %{}
      add :health, :string,
        null: false,
        check: %{
          name: "plugins_health_is_valid",
          expr: "health IN ('available', 'missing', 'version_mismatch', 'unhealthy', 'disabled')"
        }

      add :detected_at, :utc_datetime_usec, null: false
      add :last_error, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:plugins, [:key])
    create index(:plugins, [:kind, :health])

    create table(:plugin_activations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :plugin_id, references(:plugins, type: :binary_id, on_delete: :restrict), null: false
      add :scope_type, :string,
        null: false,
        check: %{
          name: "plugin_activations_scope_is_valid",
          expr: "scope_type IN ('global', 'project', 'board', 'role', 'stage')"
        }

      add :scope_id, :binary_id,
        check: %{
          name: "plugin_activations_scope_id_matches_type",
          expr:
            "(scope_type = 'global' AND scope_id IS NULL) OR " <>
              "(scope_type != 'global' AND scope_id IS NOT NULL)"
        }
      add :enabled, :boolean, null: false
      add :permissions_json, :map, null: false
      add :config_json, :map, null: false, default: %{}
      add :network, :string,
        null: false,
        check: %{
          name: "plugin_activations_network_is_valid",
          expr: "network IN ('none', 'loopback', 'external')"
        }

      add :approval_kind, :string,
        null: false,
        check: %{
          name: "plugin_activations_network_approval_matches",
          expr:
            "approval_kind IN ('standard', 'loopback_network', 'external_network') AND " <>
              "((enabled = 0 AND approval_kind = 'standard') OR " <>
              "(enabled = 1 AND network = 'none' AND approval_kind = 'standard') OR " <>
              "(enabled = 1 AND network = 'loopback' AND approval_kind = 'loopback_network') OR " <>
              "(enabled = 1 AND network = 'external' AND approval_kind = 'external_network'))"
        }

      add :approved_by, :string, null: false
      add :approval_reason, :text, null: false
      add :approved_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:plugin_activations, [:plugin_id],
             where: "scope_type = 'global'",
             name: :plugin_activations_global_plugin_index
           )

    create unique_index(:plugin_activations, [:plugin_id, :scope_type, :scope_id],
             where: "scope_type != 'global'",
             name: :plugin_activations_scoped_plugin_index
           )

    create index(:plugin_activations, [:scope_type, :scope_id])
  end
end
