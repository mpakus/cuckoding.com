defmodule Boss.Projects.Documentation do
  @moduledoc "Explicit conversion of imported documents into preserved planning references."
  import Ecto.Query
  alias Boss.{Repo, Runs, Tasks}
  alias Boss.Projects.{Project, Spec}
  alias __MODULE__.Conversion

  def convert(project, command, server \\ Runs.Manager),
    do: GenServer.call(server, {:project_documentation_convert, project, command}, 10_000)

  def get(project, command),
    do: Repo.get_by(Conversion, project_id: project, command_id: command)

  def latest(project), do: Repo.get_by(Conversion, project_id: project)
  def topic(project), do: "project-documentation:#{project}"

  def reference_only?(task),
    do: Repo.exists?(from s in "project_documentation_sources", where: s.task_id == ^task)

  def ensure_executable!(task) do
    if reference_only?(task), do: Repo.rollback(:reference_only)
  end

  def admit(project, command, owned) do
    with true <- is_integer(project) and project > 0 and is_boolean(owned),
         {:ok, ^command} <- Ecto.UUID.cast(command) do
      nested? = Repo.in_transaction?()

      result =
        transaction(fn ->
          case get(project, command) do
            %Conversion{} = saved ->
              {:existing, saved}

            nil ->
              current = Repo.get(Project, project) || Repo.rollback(:not_found)
              if current.intake_mode != "specs", do: Repo.rollback(:already_documentation)

              if owned or busy?(project), do: Repo.rollback(:busy)
              count = Repo.aggregate(from(s in Spec, where: s.project_id == ^project), :count)
              if count > 256, do: Repo.rollback(:too_many_sources)

              # The insert trigger captures all source pins and changes the mode atomically.
              saved =
                Repo.insert!(%Conversion{
                  id: Ecto.UUID.generate(),
                  project_id: project,
                  command_id: command,
                  source_count: count,
                  root_path: current.root_path,
                  git_common_dir: current.git_common_dir,
                  specs_path: current.specs_path,
                  base_branch: current.base_branch
                })

              {:new, saved}
          end
        end)

      case result do
        {:ok, {kind, saved}} ->
          if kind == :new and not nested?, do: broadcast(saved)
          {:ok, saved}

        error ->
          error
      end
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp busy?(project),
    do:
      Repo.query!(
        "SELECT EXISTS(SELECT 1 FROM documentation_conversion_busy_projects WHERE project_id=?)",
        [project]
      ).rows == [[1]]

  defp broadcast(saved) do
    Phoenix.PubSub.broadcast(
      Boss.PubSub,
      topic(saved.project_id),
      {:project_documentation, saved.project_id}
    )

    Tasks.broadcast(saved.project_id)
    Runs.broadcast(saved)
  end

  defp transaction(fun) do
    Repo.transaction(fun, mode: :immediate)
  rescue
    _ in [Exqlite.Error, Ecto.ConstraintError, DBConnection.ConnectionError] ->
      {:error, :storage_error}
  catch
    :exit, _ -> {:error, :storage_error}
  end
end
