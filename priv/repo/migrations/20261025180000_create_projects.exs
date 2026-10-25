defmodule Boss.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false
      add :root_path, :string, null: false
      add :git_common_dir, :string, null: false
      add :specs_path, :string, null: false
      add :base_branch, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:projects, [:git_common_dir])
  end
end
