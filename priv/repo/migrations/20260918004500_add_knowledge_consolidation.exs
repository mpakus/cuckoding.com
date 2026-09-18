defmodule Cuckoding.Repo.Migrations.AddKnowledgeConsolidation do
  use Ecto.Migration

  def change do
    create table(:knowledge_consolidation_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :restrict), null: false

      add :state, :string,
        null: false,
        check: %{
          name: "knowledge_consolidation_job_state_valid",
          expr: "state IN ('running', 'completed', 'failed')"
        }

      add :input_hash, :string,
        null: false,
        check: %{name: "knowledge_consolidation_job_hash_valid", expr: "length(input_hash) = 64"}

      add :policy_version, :string, null: false

      add :input_budget, :integer,
        null: false,
        check: %{
          name: "knowledge_consolidation_job_budget_valid",
          expr: "input_budget BETWEEN 1024 AND 65536"
        }

      add :revision, :integer,
        null: false,
        default: 1,
        check: %{name: "knowledge_consolidation_job_revision_positive", expr: "revision > 0"}

      add :checkpoint_json, :map, null: false, default: %{}
      add :summary_json, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:knowledge_consolidation_jobs, [:project_id])

    create table(:knowledge_index_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :consolidation_job_id,
          references(:knowledge_consolidation_jobs, type: :binary_id, on_delete: :restrict),
          null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :restrict), null: false

      add :job_revision, :integer,
        null: false,
        check: %{name: "knowledge_index_revision_positive", expr: "job_revision > 0"}

      add :previous_hash, :string,
        check: %{
          name: "knowledge_index_revision_previous_hash_valid",
          expr: "previous_hash IS NULL OR length(previous_hash) = 64"
        }

      add :content_hash, :string,
        null: false,
        check: %{
          name: "knowledge_index_revision_content_hash_valid",
          expr: "length(content_hash) = 64"
        }

      add :content, :text, null: false
      add :recorded_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:knowledge_index_revisions, [:consolidation_job_id, :job_revision])
    create unique_index(:knowledge_index_revisions, [:project_id, :job_revision])

    execute(
      """
      CREATE TRIGGER knowledge_index_revisions_no_update
      BEFORE UPDATE ON knowledge_index_revisions
      BEGIN
        SELECT RAISE(ABORT, 'knowledge_index_revisions are append-only');
      END
      """,
      "DROP TRIGGER IF EXISTS knowledge_index_revisions_no_update"
    )

    execute(
      """
      CREATE TRIGGER knowledge_index_revisions_no_delete
      BEFORE DELETE ON knowledge_index_revisions
      BEGIN
        SELECT RAISE(ABORT, 'knowledge_index_revisions are append-only');
      END
      """,
      "DROP TRIGGER IF EXISTS knowledge_index_revisions_no_delete"
    )
  end
end
