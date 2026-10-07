defmodule Cuckoding.Repo.Migrations.TabulaDrafts do
  use Ecto.Migration

  def up do
    create table(:tabulae, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :arena_id, references(:arenas, type: :binary_id), null: false
      add :team_revision_id, references(:team_revisions), null: false
      add :command_id, references(:commands, type: :binary_id), null: false
      add :name, :string, null: false
      add :definition, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:tabulae, [:command_id])
    create index(:tabulae, [:arena_id])
    create table(:draft_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tabula_id, references(:tabulae, type: :binary_id), null: false
      add :revision, :integer, null: false
      add :title, :string, null: false
      add :description, :text, null: false
      add :criteria, :text, null: false
      add :column, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:draft_tasks, [:tabula_id])
    create table(:draft_task_revisions) do
      add :task_id, references(:draft_tasks, type: :binary_id), null: false
      add :command_id, references(:commands, type: :binary_id), null: false
      add :revision, :integer, null: false
      add :content, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:draft_task_revisions, [:command_id])
    create unique_index(:draft_task_revisions, [:task_id, :revision])

    for table <- ~w(tabulae draft_task_revisions), action <- ~w(UPDATE DELETE) do
      execute "CREATE TRIGGER #{table}_no_#{String.downcase(action)} BEFORE #{action} ON #{table} BEGIN SELECT RAISE(ABORT, 'immutable draft history'); END"
    end

    for action <- ~w(INSERT UPDATE) do
      execute "CREATE TRIGGER draft_stage_#{String.downcase(action)} BEFORE #{action} ON draft_tasks WHEN NEW.column NOT IN ('specs', 'todo') OR NEW.revision < 1 BEGIN SELECT RAISE(ABORT, 'invalid draft stage'); END"
    end
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
