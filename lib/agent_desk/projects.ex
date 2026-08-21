defmodule AgentDesk.Projects do
  @moduledoc """
  Open, close, and list local Git projects.

  Project records are canonical SQLite state. Opening a project also starts a
  `ProjectRuntime` under `AgentDesk.Projects.Supervisor`.
  """

  import Ecto.Query

  require Logger

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

  @spec last_opened() :: Project.t() | nil
  def last_opened do
    Project
    |> order_by([p], desc: p.last_opened_at)
    |> limit(1)
    |> Repo.one()
  end

  @spec restore_last_opened() :: :ok | {:ok, Project.t()} | {:error, term()}
  def restore_last_opened do
    case last_opened() do
      nil -> :ok
      %Project{} = project -> restore_project(project)
    end
  end

  defp restore_project(%Project{} = project) do
    if File.dir?(project.canonical_path) and Git.repository?(project.canonical_path) do
      start_restored_runtime(ensure_open(project))
    else
      {:error, :missing_repository}
    end
  end

  defp ensure_open(%Project{open: true} = project), do: project

  defp ensure_open(project) do
    project
    |> Project.changeset(%{open: true})
    |> Repo.update!()
  end

  defp start_restored_runtime(project) do
    case ProjectSupervisor.start_runtime(project) do
      {:ok, _pid} -> {:ok, project}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec restore_on_boot() :: :ok
  def restore_on_boot do
    Enum.each(list_open(), fn project ->
      case restore_project(project) do
        {:ok, _project} -> :ok
        {:error, reason} -> log_restore(reason)
      end
    end)

    :ok
  end

  @spec list_open() :: [Project.t()]
  def list_open do
    Project
    |> where([p], p.open == true)
    |> order_by([p], desc: p.last_opened_at)
    |> Repo.all()
  end

  @spec list_recent(pos_integer()) :: [Project.t()]
  def list_recent(limit \\ @recent_limit) do
    Project
    |> order_by([p], desc: p.last_opened_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec put_settings(Project.t(), map()) :: {:ok, Project.t()} | {:error, term()}
  def put_settings(%Project{} = project, patch) when is_map(patch) do
    patch = Map.new(patch, fn {key, value} -> {to_string(key), value} end)
    merged = Map.merge(project.settings || %{}, patch)

    project
    |> Project.changeset(%{settings: merged})
    |> Repo.update()
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
      :ok = AgentDesk.Providers.stop_for_project(project.id)
      :ok = ProjectSupervisor.stop_runtime(project.id)

      project
      |> Project.changeset(%{open: false})
      |> Repo.update!()

      {:ok, _event} =
        Events.append(%{
          project_id: project.id,
          type: "project.closed",
          source: "projects",
          payload: %{"canonical_path" => project.canonical_path}
        })

      Telemetry.project_closed(project.id)
      broadcast_closed(project)
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
            default_branch: default_branch(canonical),
            last_opened_at: now,
            open: true,
            settings: %{}
          })
          |> Repo.insert!()

        %Project{} = project ->
          project
          |> Project.changeset(%{
            name: name,
            root_path: canonical,
            default_branch: default_branch(canonical),
            last_opened_at: now,
            open: true
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

  defp default_branch(canonical) do
    case Git.default_branch(canonical) do
      {:ok, name} -> name
      {:error, _} -> nil
    end
  end

  defp broadcast_opened(project) do
    Phoenix.PubSub.broadcast(AgentDesk.PubSub, "projects", {:project_opened, project})
  end

  defp broadcast_closed(project) do
    Phoenix.PubSub.broadcast(AgentDesk.PubSub, "projects", {:project_closed, project.id})
  end

  defp log_restore(reason) do
    Logger.warning("agentdesk restore skipped: #{inspect(reason)}")
  end
end
