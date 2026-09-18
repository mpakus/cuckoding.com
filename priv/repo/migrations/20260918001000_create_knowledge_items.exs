defmodule Cuckoding.Repo.Migrations.CreateKnowledgeItems do
  use Ecto.Migration

  def change do
    create table(:knowledge_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scope, :string,
        null: false,
        check: %{
          name: "knowledge_item_scope_owner_valid",
          expr:
            "(scope = 'project' AND project_id IS NOT NULL) OR " <>
              "(scope = 'global' AND project_id IS NULL)"
        }

      add :project_id, references(:projects, type: :binary_id, on_delete: :restrict)

      add :kind, :string,
        null: false,
        check: %{
          name: "knowledge_item_kind_valid",
          expr: "kind IN ('fact', 'decision', 'pattern', 'recipe', 'observation', 'skill')"
        }

      add :title, :string, null: false
      add :file_path, :text, null: false

      add :content_hash, :string,
        null: false,
        check: %{
          name: "knowledge_item_hash_lengths",
          expr:
            "length(content_hash) = 64 AND " <>
              "(observed_hash IS NULL OR length(observed_hash) = 64)"
        }

      add :observed_hash, :string

      add :sync_state, :string,
        null: false,
        default: "synced",
        check: %{
          name: "knowledge_item_sync_state_valid",
          expr: "sync_state IN ('synced', 'modified', 'missing', 'invalid')"
        }

      add :revision_source, :string,
        null: false,
        default: "user",
        check: %{
          name: "knowledge_item_revision_source_valid",
          expr: "revision_source IN ('system', 'user')"
        }

      add :status, :string,
        null: false,
        check: %{
          name: "knowledge_item_global_status_valid",
          expr:
            "(scope = 'global' AND status IN ('global', 'superseded', 'revoked')) OR " <>
              "(scope = 'project' AND status IN ('candidate', 'project', 'superseded', 'revoked'))"
        }

      add :version, :integer,
        null: false,
        check: %{name: "knowledge_item_version_positive", expr: "version > 0"}

      add :confidence, :float,
        null: false,
        check: %{
          name: "knowledge_item_confidence_valid",
          expr: "confidence >= 0.0 AND confidence <= 1.0"
        }

      add :valid_from, :utc_datetime_usec, null: false

      add :invalid_at, :utc_datetime_usec,
        check: %{
          name: "knowledge_item_validity_order",
          expr: "invalid_at IS NULL OR invalid_at >= valid_from"
        }

      add :supersedes_id,
          references(:knowledge_items, type: :binary_id, on_delete: :restrict)

      add :triggers_json, :map, null: false, default: []
      add :evidence_json, :map, null: false
      add :produced_by_json, :map, null: false
      add :review_json, :map
      add :reviewed_by, :string
      add :reviewed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:knowledge_items, [:project_id, :file_path],
             where: "scope = 'project'",
             name: :knowledge_items_project_path_index
           )

    create unique_index(:knowledge_items, [:file_path],
             where: "scope = 'global'",
             name: :knowledge_items_global_path_index
           )

    create index(:knowledge_items, [:project_id, :status, :kind])
    create index(:knowledge_items, [:scope, :status, :kind])
    create index(:knowledge_items, [:supersedes_id])
  end
end
