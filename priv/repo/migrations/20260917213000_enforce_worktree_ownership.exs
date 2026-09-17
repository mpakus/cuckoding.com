defmodule Cuckoding.Repo.Migrations.EnforceWorktreeOwnership do
  use Ecto.Migration

  def change do
    create unique_index(:environments, [:worktree_path],
             where: "state NOT IN ('stopped', 'failed')",
             name: :environments_one_active_worktree_index
           )

    create unique_index(:environments, [:run_dir],
             where: "state NOT IN ('stopped', 'failed')",
             name: :environments_one_active_run_dir_index
           )
  end
end
