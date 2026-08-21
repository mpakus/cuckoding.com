defmodule AgentDesk.Repo.Migrations.CreateUsageSamples do
  use Ecto.Migration

  def change do
    create table(:usage_samples, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_session_id,
          references(:agent_sessions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :total_tokens, :integer, null: false, default: 0
      add :cost_cents, :integer
      add :model, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:usage_samples, [:project_id, :inserted_at])
    create index(:usage_samples, [:agent_session_id, :inserted_at])
  end
end
