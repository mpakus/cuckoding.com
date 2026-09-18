defmodule Cuckoding.Repo.Migrations.CreateKnowledgeExtraction do
  use Ecto.Migration

  def change do
    create table(:knowledge_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string,
        null: false,
        default: "extract",
        check: %{name: "knowledge_job_kind_valid", expr: "kind = 'extract'"}

      add :scope_type, :string,
        null: false,
        default: "run",
        check: %{name: "knowledge_job_scope_valid", expr: "scope_type = 'run'"}

      add :scope_id, :binary_id, null: false

      add :state, :string,
        null: false,
        check: %{
          name: "knowledge_job_state_valid",
          expr: "state IN ('running', 'completed', 'failed')"
        }

      add :runtime, :string, null: false
      add :policy_version, :string, null: false

      add :input_budget, :integer,
        null: false,
        check: %{
          name: "knowledge_job_budget_valid",
          expr: "input_budget BETWEEN 1024 AND 65536"
        }

      add :input_hash, :string,
        null: false,
        check: %{name: "knowledge_job_hash_valid", expr: "length(input_hash) = 64"}

      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      add :summary_json, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:knowledge_jobs, [:kind, :scope_type, :scope_id])

    create table(:knowledge_candidates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :extraction_job_id, references(:knowledge_jobs, type: :binary_id, on_delete: :restrict), null: false
      add :project_id, references(:projects, type: :binary_id, on_delete: :restrict), null: false
      add :kind, :string,
        null: false,
        check: %{
          name: "knowledge_candidate_kind_valid",
          expr: "kind IN ('fact', 'decision', 'pattern', 'recipe', 'observation')"
        }

      add :operation, :string,
        null: false,
        check: %{
          name: "knowledge_candidate_operation_valid",
          expr: "operation IN ('add', 'update', 'supersede', 'noop')"
        }

      add :target_item_id,
          references(:knowledge_items, type: :binary_id, on_delete: :restrict),
          check: %{
            name: "knowledge_candidate_target_valid",
            expr:
              "(operation = 'add' AND target_item_id IS NULL) OR " <>
                "(operation != 'add' AND target_item_id IS NOT NULL)"
          }

      add :title, :string, null: false
      add :content, :text, null: false

      add :content_hash, :string,
        null: false,
        check: %{name: "knowledge_candidate_hash_valid", expr: "length(content_hash) = 64"}

      add :confidence, :float,
        null: false,
        check: %{
          name: "knowledge_candidate_confidence_valid",
          expr: "confidence >= 0.0 AND confidence <= 1.0"
        }

      add :evidence_json, :map, null: false

      add :redaction_state, :string,
        null: false,
        check: %{name: "knowledge_candidate_redaction_valid", expr: "redaction_state = 'redacted'"}

      add :decision, :string,
        null: false,
        default: "pending",
        check: %{
          name: "knowledge_candidate_decision_valid",
          expr: "decision IN ('pending', 'accepted', 'rejected')"
        }
      timestamps(type: :utc_datetime_usec)
    end

    create index(:knowledge_candidates, [:project_id, :decision, :kind])
    create unique_index(:knowledge_candidates, [:extraction_job_id, :content_hash, :operation])
  end
end
