defmodule Boss.Projects do
  import Ecto.Query
  alias Boss.Projects.{Project, Repository}
  alias Boss.Repo

  def list_projects, do: Repo.all(from p in Project, order_by: p.id)
  def get_project!(id), do: Repo.get!(Project, id)
  def change_project(attrs \\ %{}), do: Project.changeset(%Project{}, attrs)

  def create_project(attrs) do
    changeset = change_project(attrs)

    if changeset.valid? do
      project = Ecto.Changeset.apply_changes(changeset)

      case Repository.inspect(project.root_path, project.specs_path, project.base_branch) do
        {:ok, paths} ->
          changeset
          |> Ecto.Changeset.change(
            Map.take(paths, [:root_path, :git_common_dir, :specs_path, :base_branch])
          )
          |> Ecto.Changeset.put_change(:name, project.name || Path.basename(paths.root_path))
          |> Ecto.Changeset.validate_length(:name, max: 120)
          |> Repo.insert()

        {:error, reason} ->
          changeset
          |> Ecto.Changeset.add_error(:root_path, error_message(reason))
          |> Ecto.Changeset.apply_action(:insert)
      end
    else
      Ecto.Changeset.apply_action(changeset, :insert)
    end
  end

  defp error_message(:invalid_base_branch),
    do: "must have a local base branch with at least one commit"

  defp error_message(:specs_missing), do: "must contain an existing specs directory"
  defp error_message(:specs_symlink), do: "specs directory must not contain symlinks"
  defp error_message(:specs_outside_project), do: "specs directory must be inside the project"
  defp error_message(:invalid_specs_directory), do: "specs path must be a directory"
  defp error_message(_), do: "must be an accessible Git working tree"
end
