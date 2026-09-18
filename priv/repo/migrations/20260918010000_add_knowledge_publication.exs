defmodule Cuckoding.Repo.Migrations.AddKnowledgePublication do
  use Ecto.Migration

  def change do
    alter table(:knowledge_candidates) do
      add :accepted_item_id, references(:knowledge_items, type: :binary_id, on_delete: :restrict)
      add :reviewed_by, :string
      add :reviewed_at, :utc_datetime_usec
      add :decision_reason, :text
    end

    create table(:knowledge_publications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :candidate_id,
          references(:knowledge_candidates, type: :binary_id, on_delete: :restrict), null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :restrict), null: false

      add :knowledge_item_id,
          references(:knowledge_items, type: :binary_id, on_delete: :restrict), null: false

      add :approval_id, references(:approvals, type: :binary_id, on_delete: :restrict),
        null: false

      add :previous_publication_id,
          references(:knowledge_publications, type: :binary_id, on_delete: :restrict)

      add :action, :string,
        null: false,
        check: %{
          name: "knowledge_publication_action_valid",
          expr: "action IN ('publish', 'revoke', 'rollback')"
        }

      add :version, :integer,
        null: false,
        check: %{name: "knowledge_publication_version_positive", expr: "version > 0"}

      add :content_hash, :string,
        null: false,
        check: %{name: "knowledge_publication_hash_valid", expr: "length(content_hash) = 64"}

      add :content, :text, null: false
      add :actor, :string, null: false
      add :reason, :text, null: false
      add :recorded_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:knowledge_publications, [:approval_id])
    create unique_index(:knowledge_publications, [:knowledge_item_id, :version])

    create unique_index(:knowledge_publications, [:candidate_id],
             where: "action = 'publish'",
             name: :knowledge_publications_one_publish_per_candidate_index
           )

    create index(:knowledge_publications, [:project_id, :recorded_at])

    create table(:skill_packages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :knowledge_item_id,
          references(:knowledge_items, type: :binary_id, on_delete: :restrict), null: false

      add :publication_id,
          references(:knowledge_publications, type: :binary_id, on_delete: :restrict), null: false

      add :name, :string, null: false
      add :version, :string, null: false
      add :file_path, :text, null: false
      add :manifest_json, :map, null: false
      add :content_hash, :string, null: false
      add :published_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:skill_packages, [:name, :version])
    create unique_index(:skill_packages, [:publication_id])

    for table <- ~w(knowledge_publications skill_packages) do
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
