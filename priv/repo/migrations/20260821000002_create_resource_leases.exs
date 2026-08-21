defmodule AgentDesk.Repo.Migrations.CreateResourceLeases do
  use Ecto.Migration

  def change do
    create table(:resource_leases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_session_id,
          references(:agent_sessions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :resource_type, :text, null: false
      add :resource_key, :text, null: false
      add :mode, :text, null: false
      add :status, :text, null: false
      add :reason, :text, null: false
      add :acquired_at, :utc_datetime_usec, null: false
      add :renewed_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :released_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:resource_leases, [:project_id, :resource_type, :resource_key, :status])
    create index(:resource_leases, [:agent_session_id, :status])
    create index(:resource_leases, [:status, :expires_at])
  end
end
