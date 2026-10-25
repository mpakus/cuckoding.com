defmodule Boss.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  schema "projects" do
    field :name, :string
    field :root_path, :string
    field :git_common_dir, :string
    field :specs_path, :string, default: "specs"
    field :base_branch, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :root_path, :specs_path, :base_branch])
    |> validate_required([:root_path, :specs_path])
    |> validate_length(:name, max: 120)
    |> validate_length(:root_path, max: 4096)
    |> validate_length(:specs_path, max: 4096)
    |> validate_length(:base_branch, max: 255)
    |> unique_constraint(:git_common_dir)
  end
end
