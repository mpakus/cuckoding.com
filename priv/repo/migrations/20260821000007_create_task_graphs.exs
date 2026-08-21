defmodule AgentDesk.Repo.Migrations.CreateTaskGraphs do
  use Ecto.Migration

  def change do
    create table(:task_dependencies, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false

      add :depends_on_id, references(:tasks, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:task_dependencies, [:task_id, :depends_on_id])
    create index(:task_dependencies, [:project_id, :depends_on_id])
    create index(:task_dependencies, [:project_id, :task_id])

    create table(:workflow_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :text, null: false
      add :description, :text, null: false, default: ""
      add :definition, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:workflow_templates, [:project_id, :name])
  end
end
