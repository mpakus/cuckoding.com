defmodule Cuckoding.Repo.Migrations.Foundation do
  use Ecto.Migration

  def up do
    create table(:workspace, primary_key: false) do
      add :id, :integer, primary_key: true
      add :revision, :integer, null: false, default: 0
      add :tools, :map, null: false, default: %{}
      add :checked_at, :utc_datetime_usec
    end
    execute "INSERT INTO workspace (id, revision, tools) VALUES (1, 0, '{}')"

    create table(:commands, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :expected_revision, :integer, null: false
      add :state, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :lease_until, :integer
      add :result, :string
      timestamps(type: :utc_datetime_usec)
    end

    create table(:events) do
      add :command_id, references(:commands, type: :binary_id)
      add :kind, :string, null: false
      add :data, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
    end
    execute "CREATE TRIGGER events_no_update BEFORE UPDATE ON events BEGIN SELECT RAISE(ABORT, 'append-only events'); END"
    execute "CREATE TRIGGER events_no_delete BEFORE DELETE ON events BEGIN SELECT RAISE(ABORT, 'append-only events'); END"

    create table(:browser_tokens, primary_key: false) do
      add :digest, :binary, primary_key: true
      add :kind, :string, null: false
      add :expires_at, :integer, null: false
    end
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
