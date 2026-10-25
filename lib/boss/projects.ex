defmodule Boss.Projects do
  import Ecto.Query
  alias Boss.Projects.{Project, Repository, Spec, SpecRevision}
  alias Boss.Repo
  alias Boss.Tasks.Task

  def list_projects, do: Repo.all(from p in Project, order_by: p.id)
  def get_project!(id), do: Repo.get!(Project, id)
  def change_project(attrs \\ %{}), do: Project.changeset(%Project{}, attrs)

  @doc """
  Records one source observation atomically. Attributes: relative_path,
  original_text, title and optional explicit_id. Returns :created, :unchanged
  or :revised in result.change. A task stays pinned to its initial revision.

  This is persistence only: callers must read/validate files separately. A path
  claiming another identity is rejected; rename reconciliation is not implicit.
  """
  def record_spec(project_id, attrs) do
    spec_changeset = Spec.changeset(project_id, attrs)
    source_changeset = SpecRevision.source_changeset(attrs)

    with {:ok, input} <- Ecto.Changeset.apply_action(spec_changeset, :insert),
         {:ok, source} <- Ecto.Changeset.apply_action(source_changeset, :insert) do
      Repo.transaction(
        fn ->
          unless Repo.get(Project, input.project_id) do
            Repo.rollback(Ecto.Changeset.add_error(spec_changeset, :project_id, "does not exist"))
          end

          spec = Repo.get_by(Spec, project_id: input.project_id, identity_key: input.identity_key)

          if spec && spec.relative_path != input.relative_path do
            Repo.rollback(
              Ecto.Changeset.add_error(
                spec_changeset,
                :relative_path,
                "ID already belongs to another path"
              )
            )
          end

          spec = spec || insert_record(spec_changeset)

          latest =
            Repo.one(
              from r in SpecRevision,
                where: r.spec_id == ^spec.id,
                order_by: [desc: r.number],
                limit: 1
            )

          unchanged? =
            latest && latest.content_hash == source.content_hash &&
              latest.original_text == source.original_text

          revision =
            if unchanged? do
              latest
            else
              source_changeset
              |> Ecto.Changeset.change(
                spec_id: spec.id,
                relative_path: spec.relative_path,
                number: if(latest, do: latest.number + 1, else: 1)
              )
              |> insert_record()
            end

          task =
            Repo.get_by(Task, spec_id: spec.id) ||
              insert_record(Task.changeset(spec, revision, attrs))

          change =
            cond do
              is_nil(latest) -> :created
              unchanged? -> :unchanged
              true -> :revised
            end

          %{spec: spec, revision: revision, task: task, change: change}
        end,
        mode: :immediate
      )
    end
  end

  def list_spec_revisions(spec_id),
    do: Repo.all(from r in SpecRevision, where: r.spec_id == ^spec_id, order_by: r.number)

  defp insert_record(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, error} -> Repo.rollback(error)
    end
  end

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
