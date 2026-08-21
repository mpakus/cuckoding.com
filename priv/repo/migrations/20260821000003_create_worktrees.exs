defmodule AgentDesk.Repo.Migrations.CreateWorktrees do
  use Ecto.Migration

  def change do
    create table(:worktrees, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_session_id,
          references(:agent_sessions, type: :binary_id, on_delete: :nilify_all)

      add :path, :text, null: false
      add :branch_name, :text, null: false
      add :base_commit, :text, null: false
      add :head_commit, :text
      add :status, :text, null: false
      add :app_owned, :boolean, null: false, default: true
      add :last_scanned_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:worktrees, [:path])
    create unique_index(:worktrees, [:project_id, :branch_name])
    create index(:worktrees, [:project_id, :status])

    create unique_index(:worktrees, [:agent_session_id],
             where: "agent_session_id IS NOT NULL AND status NOT IN ('removed', 'removing')"
           )
  end
end
