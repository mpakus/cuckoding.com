defmodule Cuckoding.Repo.Migrations.AddKnowledgeUsage do
  use Ecto.Migration

  def change do
    create table(:knowledge_retrieval_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :restrict), null: false

      add :stage_attempt_id,
          references(:stage_attempts, type: :binary_id, on_delete: :restrict), null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :restrict), null: false
      add :token_hash, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:knowledge_retrieval_tokens, [:token_hash])
    create index(:knowledge_retrieval_tokens, [:run_id, :stage_attempt_id])

    create table(:knowledge_retrievals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :restrict), null: false

      add :stage_attempt_id,
          references(:stage_attempts, type: :binary_id, on_delete: :restrict), null: false

      add :backend_key, :string, null: false
      add :namespace, :string, null: false
      add :query_hash, :string, null: false
      add :hit_count, :integer, null: false
      add :context_bytes, :integer, null: false
      add :selected_ids_json, :map, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:knowledge_retrievals, [:run_id, :stage_attempt_id, :occurred_at])

    create table(:knowledge_usages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :knowledge_item_id,
          references(:knowledge_items, type: :binary_id, on_delete: :restrict), null: false

      add :item_version, :integer, null: false
      add :run_id, references(:runs, type: :binary_id, on_delete: :restrict), null: false

      add :stage_attempt_id,
          references(:stage_attempts, type: :binary_id, on_delete: :restrict), null: false

      add :kind, :string,
        null: false,
        check: %{
          name: "knowledge_usage_kind_valid",
          expr: "kind IN ('injected', 'retrieved', 'cited', 'accepted', 'contradicted')"
        }

      add :event_key_hash, :string, null: false
      add :evidence_json, :map, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:knowledge_usages, [:event_key_hash])
    create index(:knowledge_usages, [:knowledge_item_id, :item_version, :kind])
    create index(:knowledge_usages, [:run_id, :stage_attempt_id, :occurred_at])

    for table <- ~w(knowledge_retrievals knowledge_usages) do
      execute(
        """
        CREATE TRIGGER #{table}_no_update
        BEFORE UPDATE ON #{table}
        BEGIN
          SELECT RAISE(ABORT, '#{table} are append-only');
        END
        """,
        "DROP TRIGGER IF EXISTS #{table}_no_update"
      )

      execute(
        """
        CREATE TRIGGER #{table}_no_delete
        BEFORE DELETE ON #{table}
        BEGIN
          SELECT RAISE(ABORT, '#{table} are append-only');
        END
        """,
        "DROP TRIGGER IF EXISTS #{table}_no_delete"
      )
    end
  end
end
