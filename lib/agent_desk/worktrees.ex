defmodule AgentDesk.Worktrees do
  @moduledoc """
  One linked Git worktree and branch per agent session.
  """

  import Ecto.Query

  alias AgentDesk.Agents.Session
  alias AgentDesk.Clock
  alias AgentDesk.Git
  alias AgentDesk.Ids
  alias AgentDesk.Projects.Project
  alias AgentDesk.Repo
  alias AgentDesk.Storage
  alias AgentDesk.Worktrees.Worktree

  @spec shared_mode?() :: boolean()
  def shared_mode? do
    Application.get_env(:agent_desk, :features, [])[:shared_workspace_mode] == true
  end

  @spec ensure_for_session(Project.t(), Session.t()) ::
          {:ok, Worktree.t() | nil} | {:error, term()}
  def ensure_for_session(%Project{} = project, %Session{} = session) do
    if shared_mode?() do
      {:ok, nil}
    else
      create_or_get(project, session)
    end
  end

  @spec working_copy_path(Project.t(), Session.t()) :: String.t()
  def working_copy_path(%Project{} = project, %Session{} = session) do
    case get_for_session(session.id) do
      %Worktree{path: path, status: status} when status not in ["removed", "removing"] -> path
      _ -> project.canonical_path
    end
  end

  @spec get_for_session(Ecto.UUID.t()) :: Worktree.t() | nil
  def get_for_session(session_id) do
    Worktree
    |> where(
      [w],
      w.agent_session_id == ^session_id and w.status not in ["removed", "removing"]
    )
    |> Repo.one()
  end

  @spec list_project(Ecto.UUID.t()) :: [Worktree.t()]
  def list_project(project_id) do
    Worktree
    |> where([w], w.project_id == ^project_id and w.status not in ["removed"])
    |> order_by([w], asc: w.inserted_at)
    |> Repo.all()
  end

  @spec scan(Worktree.t()) :: {:ok, Worktree.t()} | {:error, term()}
  def scan(%Worktree{} = worktree) do
    now = Clock.utc_now()

    cond do
      not File.dir?(worktree.path) ->
        update_status(worktree, "stale", now)

      Git.conflicted?(worktree.path) ->
        update_head(worktree, "conflicted", now)

      Git.dirty?(worktree.path) ->
        update_head(worktree, "dirty", now)

      true ->
        status = if worktree.status in ["handed_off", "stale"], do: worktree.status, else: "ready"
        update_head(worktree, status, now)
    end
  end

  @spec reconcile(Project.t()) :: :ok
  def reconcile(%Project{} = project) do
    Enum.each(list_project(project.id), &scan/1)
    :ok
  end

  @spec commit(Worktree.t(), String.t()) :: {:ok, Worktree.t()} | {:error, term()}
  def commit(%Worktree{} = worktree, message) do
    with {:ok, sha} <- Git.commit_all(worktree.path, message) do
      worktree
      |> Worktree.changeset(%{
        head_commit: sha,
        status: "ready",
        last_scanned_at: Clock.utc_now()
      })
      |> Repo.update()
    end
  end

  @spec cleanup(Project.t(), Worktree.t()) :: :ok | {:error, term()}
  def cleanup(%Project{} = project, %Worktree{} = worktree) do
    cond do
      worktree.app_owned != true ->
        {:error, :not_app_owned}

      Path.expand(worktree.path) != worktree.path ->
        {:error, :path_mismatch}

      Git.dirty?(worktree.path) ->
        {:error, :dirty}

      not Git.linked_worktree?(project.canonical_path, worktree.path) ->
        {:error, :not_linked}

      true ->
        with :ok <- Git.worktree_remove(project.canonical_path, worktree.path) do
          {:ok, _} = update_status(worktree, "removed", Clock.utc_now())
          :ok
        end
    end
  end

  @spec unexpected_main_edits(Project.t()) :: [String.t()]
  def unexpected_main_edits(%Project{} = project) do
    isolated? = list_project(project.id) != []

    case {isolated?, Git.status_porcelain(project.canonical_path)} do
      {true, {:ok, status}} when status != "" -> String.split(status, "\n", trim: true)
      _ -> []
    end
  end

  defp create_or_get(project, session) do
    case get_for_session(session.id) do
      %Worktree{} = existing -> {:ok, existing}
      nil -> create!(project, session)
    end
  end

  defp create!(project, session) do
    with {:ok, base} <- Git.rev_parse(project.canonical_path, "HEAD") do
      path = Path.expand(Storage.worktree_dir(project.id, session.id))
      branch = "agentdesk/" <> session.id
      File.mkdir_p!(Path.dirname(path))

      case Git.worktree_add(project.canonical_path, path, branch) do
        {:ok, _} ->
          insert_worktree(project, session, path, branch, base)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp insert_worktree(project, session, path, branch, base) do
    %Worktree{}
    |> Worktree.changeset(%{
      id: Ids.generate(),
      project_id: project.id,
      agent_session_id: session.id,
      path: path,
      branch_name: branch,
      base_commit: base,
      head_commit: base,
      status: "ready",
      app_owned: true,
      last_scanned_at: Clock.utc_now()
    })
    |> Repo.insert()
  end

  defp update_status(worktree, status, now) do
    worktree
    |> Worktree.changeset(%{status: status, last_scanned_at: now})
    |> Repo.update()
  end

  defp update_head(worktree, status, now) do
    head =
      case Git.rev_parse(worktree.path, "HEAD") do
        {:ok, sha} -> sha
        {:error, _} -> worktree.head_commit
      end

    worktree
    |> Worktree.changeset(%{status: status, head_commit: head, last_scanned_at: now})
    |> Repo.update()
  end
end
