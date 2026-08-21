defmodule AgentDesk.Projects do
  @moduledoc """
  Open, close, and list local Git projects.

  Project records are canonical SQLite state. Opening a project also starts a
  `ProjectRuntime` under `AgentDesk.Projects.Supervisor`.
  """

  import Ecto.Query

  alias AgentDesk.Clock
  alias AgentDesk.Events
  alias AgentDesk.Git
  alias AgentDesk.Ids
  alias AgentDesk.Paths
  alias AgentDesk.Projects.Project
  alias AgentDesk.Projects.Supervisor, as: ProjectSupervisor
  alias AgentDesk.Repo
  alias AgentDesk.Telemetry

  @recent_limit 20

  @spec list_recent(pos_integer()) :: [Project.t()]
  def list_recent(limit \\ @recent_limit) do
    Project
    |> order_by([p], desc: p.last_opened_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec get_project(Ecto.UUID.t()) :: {:ok, Project.t()} | {:error, :not_found}
  def get_project(id) when is_binary(id) do
    case Repo.get(Project, id) do
      %Project{} = project -> {:ok, project}
      nil -> {:error, :not_found}
    end
  end

  @spec open_project(Path.t()) :: {:ok, Project.t()} | {:error, term()}
  def open_project(path) when is_binary(path) do
    with {:ok, canonical} <- Paths.canonicalize(path),
         :ok <- validate_git(canonical) do
      persist_and_start(canonical)
    end
  end

  @spec close_project(Project.t() | Ecto.UUID.t()) :: :ok | {:error, term()}
  def close_project(%Project{} = project), do: close_project(project.id)

  def close_project(project_id) when is_binary(project_id) do
    with {:ok, project} <- get_project(project_id) do
      :ok = ProjectSupervisor.stop_runtime(project.id)

      {:ok, _event} =
        Events.append(%{
          project_id: project.id,
          type: "project.closed",
          source: "projects",
          payload: %{"canonical_path" => project.canonical_path}
        })

      Telemetry.project_closed(project.id)
      :ok
    end
  end

  defp validate_git(canonical) do
    if Git.repository?(canonical) do
      :ok
    else
      {:error, :not_a_git_repository}
    end
  end

  defp persist_and_start(canonical) do
    now = Clock.utc_now()
    name = Path.basename(canonical)

    case Repo.transaction(fn -> persist_open(canonical, name, now) end) do
      {:ok, project} ->
        {:ok, _pid} = ProjectSupervisor.start_runtime(project)
        Telemetry.project_opened(project.id)
        broadcast_opened(project)
        {:ok, project}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_open(canonical, name, now) do
    project =
      case Repo.get_by(Project, canonical_path: canonical) do
        nil ->
          %Project{id: Ids.generate()}
          |> Project.changeset(%{
            name: name,
            root_path: canonical,
            canonical_path: canonical,
            vcs_type: "git",
            last_opened_at: now,
            settings: %{}
          })
          |> Repo.insert!()

        %Project{} = project ->
          project
          |> Project.changeset(%{
            name: name,
            root_path: canonical,
            last_opened_at: now
          })
          |> Repo.update!()
      end

    {:ok, _event} =
      Events.append(%{
        id: Ids.generate(),
        project_id: project.id,
        type: "project.opened",
        source: "projects",
        occurred_at: now,
        payload: %{"canonical_path" => canonical}
      })

    project
  end

  defp broadcast_opened(project) do
    Phoenix.PubSub.broadcast(AgentDesk.PubSub, "projects", {:project_opened, project})
  end
end
