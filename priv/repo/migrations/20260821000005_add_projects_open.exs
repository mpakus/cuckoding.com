defmodule AgentDesk.Repo.Migrations.AddProjectsOpen do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :open, :boolean, null: false, default: false
    end

    create index(:projects, [:open])

    execute(
      "UPDATE projects SET open = 1 WHERE id IN (SELECT id FROM projects ORDER BY last_opened_at DESC LIMIT 1)",
      "UPDATE projects SET open = 0"
    )
  end
end
