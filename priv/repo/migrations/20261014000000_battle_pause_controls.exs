defmodule Cuckoding.Repo.Migrations.BattlePauseControls do
  use Ecto.Migration

  def up do
    alter table(:battles) do
      add :control_revision, :integer, null: false, default: 0
    end

    drop index(:battles, [:arena_id], name: :battles_one_active_arena)

    create unique_index(:battles, [:arena_id],
             name: :battles_one_active_arena,
             where: "state IN ('running', 'pausing', 'paused', 'stopping', 'needs_attention')"
           )
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
