defmodule Cuckoding.Repo.Migrations.ParallelTaskClaims do
  use Ecto.Migration

  def up do
    drop index(:battle_attempts, [:battle_id], name: :battle_attempts_one_running)

    create unique_index(:battle_attempts, [:battle_id, :task_id],
             name: :battle_attempts_one_running_task,
             where: "state = 'running' AND task_id IS NOT NULL"
           )

    create unique_index(:battle_attempts, [:battle_id],
             name: :battle_attempts_one_running_final,
             where: "state = 'running' AND task_id IS NULL"
           )
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
