defmodule Cuckoding.Repo.Migrations.Battles do
  use Ecto.Migration

  def up do
    create table(:battles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :arena_id, references(:arenas, type: :binary_id), null: false
      add :tabula_id, references(:tabulae, type: :binary_id), null: false
      add :fingerprint, :string, null: false
      add :snapshot, :map, null: false
      add :context, :map, null: false, default: %{}
      add :state, :string, null: false
      add :stage, :string, null: false
      add :current_task_id, references(:draft_tasks, type: :binary_id)
      add :turns_used, :integer, null: false, default: 0
      add :deadline_at, :utc_datetime_usec, null: false
      add :reason, :string
      timestamps(type: :utc_datetime_usec)
    end

    create index(:battles, [:tabula_id, :inserted_at])

    create unique_index(:battles, [:arena_id],
             name: :battles_one_active_arena,
             where: "state IN ('running', 'stopping', 'needs_attention')"
           )

    create table(:battle_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :battle_id, references(:battles, type: :binary_id), null: false
      add :task_id, references(:draft_tasks, type: :binary_id), null: false
      add :position, :integer, null: false
      add :snapshot, :map, null: false
      add :context, :map, null: false, default: %{}
      add :state, :string, null: false, default: "pending"
      add :review_round, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:battle_tasks, [:battle_id, :task_id])
    create unique_index(:battle_tasks, [:battle_id, :position])

    create table(:battle_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :battle_id, references(:battles, type: :binary_id), null: false
      add :task_id, references(:draft_tasks, type: :binary_id)
      add :stage, :string, null: false
      add :role, :string
      add :state, :string, null: false
      add :claim_token, :binary_id, null: false
      add :request, :map, null: false
      add :result, :map, null: false, default: %{}
      add :deadline_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:battle_attempts, [:battle_id, :inserted_at])

    create unique_index(:battle_attempts, [:battle_id],
             name: :battle_attempts_one_running,
             where: "state = 'running'"
           )

    for {table, columns} <- [
          {"battles", "id, arena_id, tabula_id, fingerprint, snapshot, deadline_at"},
          {"battle_tasks", "id, battle_id, task_id, position, snapshot"},
          {"battle_attempts",
           "id, battle_id, task_id, stage, role, claim_token, request, deadline_at"}
        ] do
      execute "CREATE TRIGGER #{table}_authority_immutable BEFORE UPDATE OF #{columns} ON #{table} BEGIN SELECT RAISE(ABORT, 'immutable battle authority'); END"

      execute "CREATE TRIGGER #{table}_no_delete BEFORE DELETE ON #{table} BEGIN SELECT RAISE(ABORT, 'retained battle evidence'); END"
    end

    execute "CREATE TRIGGER battle_attempts_terminal BEFORE UPDATE ON battle_attempts WHEN OLD.state != 'running' BEGIN SELECT RAISE(ABORT, 'immutable attempt outcome'); END"
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
