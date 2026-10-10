defmodule Cuckoding.Repo.Migrations.AgentConnections do
  use Ecto.Migration

  def change do
    create table(:agent_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      add :kind, :text, null: false
      add :codex, :map, null: false, default: %{}
      add :connection, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    execute "CREATE TRIGGER agent_kind BEFORE INSERT ON agent_connections WHEN NEW.kind NOT IN ('codex', 'cursor') BEGIN SELECT RAISE(ABORT, 'unknown runtime'); END", "DROP TRIGGER agent_kind"
  end
end
