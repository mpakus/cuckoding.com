defmodule AgentDesk.Repo.Migrations.CreateMergeQueue do
  use Ecto.Migration

  def change do
    create table(:merge_queue_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :artifact_id, references(:artifacts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_session_id,
          references(:agent_sessions, type: :binary_id, on_delete: :nilify_all)

      add :worktree_id, references(:worktrees, type: :binary_id, on_delete: :nilify_all)

      add :branch_name, :text, null: false
      add :commit_sha, :text, null: false
      add :target_ref, :text, null: false
      add :summary, :text, null: false
      add :status, :text, null: false
      add :policy_status, :text, null: false
      add :policy_report, :map, null: false, default: %{}
      add :accepted_by_id, :binary_id
      add :merged_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:merge_queue_items, [:artifact_id])
    create index(:merge_queue_items, [:project_id, :status])
  end
end
