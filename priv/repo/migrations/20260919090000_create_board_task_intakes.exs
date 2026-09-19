defmodule Cuckoding.Repo.Migrations.CreateBoardTaskIntakes do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :kind, :string,
        null: false,
        default: "delivery",
        check: %{name: "task_kind_is_valid", expr: "kind IN ('delivery', 'board_intake')"}

      add :intake_role_key, :string
    end

    create table(:task_proposals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :intake_task_id, references(:tasks, type: :binary_id, on_delete: :restrict), null: false
      add :position, :integer,
        null: false,
        check: %{name: "task_proposal_position_is_non_negative", expr: "position >= 0"}

      add :title, :string, null: false
      add :description, :text
      add :priority, :integer,
        null: false,
        default: 0,
        check: %{
          name: "task_proposal_priority_is_bounded",
          expr: "priority BETWEEN -100 AND 100"
        }

      add :source_json, :map, null: false, default: %{}
      add :imported_task_id, references(:tasks, type: :binary_id, on_delete: :restrict)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:task_proposals, [:intake_task_id, :position])
    create unique_index(:task_proposals, [:imported_task_id], where: "imported_task_id IS NOT NULL")
  end
end
