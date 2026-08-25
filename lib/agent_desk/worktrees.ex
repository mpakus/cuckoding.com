defmodule AgentDesk.Worktrees do
  @moduledoc """
  One linked Git worktree and branch per agent session.
  """

  import Ecto.Query

  alias AgentDesk.Agents.Session
  alias AgentDesk.Clock
  alias AgentDesk.Git
  alias AgentDesk.Ids
  alias AgentDesk.Paths
  alias AgentDesk.Projects.Project
  alias AgentDesk.Repo
  alias AgentDesk.Storage
  alias AgentDesk.Worktrees.Worktree

  @spec shared_mode?() :: boolean()
  def shared_mode? do
    Application.get_env(:agent_desk, :features, [])[:shared_workspace_mode] == true
  end

  @spec shared_session?(Session.t()) :: boolean()
  def shared_session?(%Session{settings: settings}) when is_map(settings) do
    settings["shared"] in [true, "true"]
  end

  def shared_session?(%Session{}), do: false

  @spec ensure_for_session(Project.t(), Session.t()) ::
          {:ok, Worktree.t() | nil} | {:error, term()}
  def ensure_for_session(%Project{} = project, %Session{} = session) do
    if shared_mode?() or shared_session?(session) do
      {:ok, nil}
    else
      create_or_get(project, session)
    end
  end

  @spec working_copy_path(Project.t(), Session.t()) :: String.t()
  def working_copy_path(%Project{} = project, %Session{} = session) do
    case get_for_session(session.id) do
      %Worktree{path: path, status: status} when status not in ["removed", "removing"] ->
        path

      _ ->
        if shared_mode?() or shared_session?(session) do
          project.canonical_path
        else
          Path.expand(Storage.worktree_dir(project.id, session.id))
        end
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

      worktree.project_id != project.id ->
        {:error, :project_mismatch}

      worktree.path != expected_worktree_path(worktree) ->
        {:error, :path_mismatch}

      not canonical_worktree_path?(worktree.path) ->
        {:error, :path_mismatch}

      owning_session_live?(worktree.agent_session_id) ->
        {:error, :session_live}

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

  @spec validate_for_resume(Project.t(), Session.t()) :: :ok | {:error, term()}
  def validate_for_resume(%Project{} = project, %Session{} = session) do
    case get_for_session(session.id) do
      %Worktree{} ->
        validate_isolated_resume(project, session)

      nil ->
        if shared_mode?() or shared_session?(session) do
          validate_shared_resume(project)
        else
          {:error, :invalid_worktree}
        end
    end
  end

  @doc false
  @spec discard_start_attempt(Project.t(), Session.t(), Worktree.t(), keyword()) ::
          :ok | {:error, term()}
  def discard_start_attempt(
        %Project{} = project,
        %Session{} = session,
        %Worktree{} = worktree,
        opts \\ []
      ) do
    expected_path = Path.expand(Storage.worktree_dir(project.id, session.id))
    expected_branch = "agentdesk/" <> session.id
    external_process_started? = Keyword.get(opts, :external_process_started?, false)

    if worktree.app_owned == true and worktree.project_id == project.id and
         worktree.agent_session_id == session.id and worktree.path == expected_path and
         worktree.branch_name == expected_branch do
      discard_owned_start_attempt(project, worktree, external_process_started?)
    else
      {:error, :not_start_attempt_resource}
    end
  end

  defp discard_owned_start_attempt(project, worktree, external_process_started?) do
    cond do
      File.dir?(worktree.path) and Git.dirty?(worktree.path) ->
        {:ok, _} = update_status(worktree, "dirty", Clock.utc_now())
        {:error, if(external_process_started?, do: :dirty_after_process_start, else: :dirty)}

      Git.linked_worktree?(project.canonical_path, worktree.path) ->
        with :ok <- Git.worktree_remove(project.canonical_path, worktree.path),
             :ok <- Git.delete_branch(project.canonical_path, worktree.branch_name),
             {:ok, _} <- Repo.delete(worktree) do
          :ok
        end

      File.exists?(worktree.path) ->
        {:error, :not_linked}

      true ->
        with :ok <- Git.delete_branch(project.canonical_path, worktree.branch_name),
             {:ok, _} <- Repo.delete(worktree) do
          :ok
        end
    end
  end

  defp validate_shared_resume(%Project{} = project) do
    if File.dir?(project.canonical_path), do: :ok, else: {:error, :worktree_missing}
  end

  defp validate_isolated_resume(%Project{} = project, %Session{} = session) do
    expected_path = Path.expand(Storage.worktree_dir(project.id, session.id))

    case get_for_session(session.id) do
      %Worktree{
        project_id: project_id,
        agent_session_id: session_id,
        path: path,
        app_owned: true,
        status: status
      }
      when project_id == project.id and session_id == session.id and path == expected_path and
             status not in ["stale", "removing", "removed"] ->
        with true <- File.dir?(path),
             {:ok, canonical} <- Paths.canonicalize(path),
             true <- canonical == path,
             true <- Git.linked_worktree?(project.canonical_path, path) do
          :ok
        else
          false -> {:error, :invalid_worktree}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :invalid_worktree}
    end
  end

  defp expected_worktree_path(%Worktree{} = worktree) do
    Path.expand(Storage.worktree_dir(worktree.project_id, worktree.agent_session_id))
  end

  defp canonical_worktree_path?(path) do
    case AgentDesk.Paths.canonicalize(path) do
      {:ok, canonical} -> canonical == path
      {:error, _reason} -> false
    end
  end

  defp owning_session_live?(session_id) do
    case Repo.get(Session, session_id) do
      %Session{status: status} ->
        status in ~w(queued starting idle working waiting blocked terminating)

      nil ->
        false
    end
  end

  @spec unexpected_main_edits(Project.t()) :: [String.t()]
  def unexpected_main_edits(%Project{} = project) do
    isolated? = list_project(project.id) != []

    case {isolated?, Git.status_porcelain(project.canonical_path)} do
      {true, {:ok, status}} when status != "" ->
        status
        |> String.split("\n", trim: true)
        |> reject_untracked_on_empty_repo(project)

      _ ->
        []
    end
  end

  defp reject_untracked_on_empty_repo(lines, project) do
    case Git.rev_parse(project.canonical_path, "HEAD") do
      {:error, :empty_repository} -> Enum.reject(lines, &String.starts_with?(&1, "?? "))
      _ -> lines
    end
  end

  defp create_or_get(project, session) do
    case get_for_session(session.id) do
      %Worktree{} = existing -> {:ok, existing}
      nil -> create!(project, session)
    end
  end

  defp create!(project, session) do
    path = Path.expand(Storage.worktree_dir(project.id, session.id))
    branch = "agentdesk/" <> session.id
    File.mkdir_p!(Path.dirname(path))

    case Git.rev_parse(project.canonical_path, "HEAD") do
      {:ok, base} ->
        add_and_insert(project, session, path, branch, base, :head)

      {:error, :empty_repository} ->
        add_and_insert(project, session, path, branch, Git.empty_tree_id(), :orphan)

      error ->
        error
    end
  end

  defp add_and_insert(project, session, path, branch, fallback_base, mode) do
    result =
      case mode do
        :head -> Git.worktree_add(project.canonical_path, path, branch)
        :orphan -> Git.worktree_add_orphan(project.canonical_path, path, branch)
      end

    case result do
      {:ok, _} ->
        if mode == :orphan do
          seed_untracked(project.canonical_path, path)
        end

        base =
          case Git.rev_parse(path, "HEAD") do
            {:ok, sha} -> sha
            _ -> fallback_base
          end

        case insert_worktree(project, session, path, branch, base) do
          {:ok, _worktree} = ok ->
            ok

          {:error, _reason} = error ->
            _ = Git.worktree_remove_force(project.canonical_path, path)
            _ = File.rm_rf(path)
            _ = Git.delete_branch(project.canonical_path, branch)
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp seed_untracked(repo, worktree_path) do
    with {:ok, source_root} <- Paths.canonicalize(repo),
         {:ok, destination_root} <- Paths.canonicalize(worktree_path),
         {:ok, files} <- Git.untracked_files(source_root) do
      Enum.each(files, &seed_untracked_file(source_root, destination_root, &1))
    end

    :ok
  end

  defp seed_untracked_file(source_root, destination_root, relative_path) do
    source_path = Path.expand(relative_path, source_root)
    destination_path = Path.expand(relative_path, destination_root)

    with true <- Path.type(relative_path) == :relative,
         {:ok, canonical_source} <- Paths.safe_path(source_root, relative_path),
         {:ok, canonical_destination} <- Paths.safe_path(destination_root, relative_path),
         {:ok, source_before} <- File.lstat(source_path),
         :ok <- require_regular(source_before),
         {:ok, canonical_before} <- File.lstat(canonical_source),
         :ok <- require_regular(canonical_before),
         :ok <- verify_file_identity(source_before, canonical_before),
         {:error, :enoent} <- File.lstat(destination_path),
         :ok <-
           copy_stable_regular(
             source_root,
             relative_path,
             canonical_source,
             canonical_before,
             destination_root,
             canonical_destination
           ) do
      :ok
    else
      _reason -> :ok
    end
  end

  defp copy_stable_regular(
         source_root,
         relative_path,
         source_path,
         source_before,
         destination_root,
         destination_path
       ) do
    case :file.open(source_path, [:read, :binary, :raw, :nofollow, :nonblock]) do
      {:ok, source_io} ->
        try do
          with {:ok, opened_source} <- descriptor_stat(source_io),
               :ok <- require_regular(opened_source),
               :ok <- verify_file_identity(source_before, opened_source),
               :ok <- prepare_destination(destination_root, relative_path, destination_path),
               :ok <-
                 copy_to_new_destination(
                   source_io,
                   source_root,
                   relative_path,
                   source_path,
                   opened_source,
                   destination_root,
                   destination_path
                 ) do
            :ok
          end
        after
          _ = :file.close(source_io)
        end

      {:error, _reason} ->
        {:error, :source_open_failed}
    end
  end

  defp prepare_destination(destination_root, relative_path, destination_path) do
    parent_relative = Path.dirname(relative_path)

    with {:ok, parent_before} <- Paths.safe_path(destination_root, parent_relative),
         :ok <- File.mkdir_p(parent_before),
         {:ok, ^parent_before} <- Paths.safe_path(destination_root, parent_relative),
         {:ok, ^destination_path} <- Paths.safe_path(destination_root, relative_path),
         {:error, :enoent} <- File.lstat(destination_path) do
      :ok
    else
      _reason -> {:error, :destination_forbidden}
    end
  end

  defp copy_to_new_destination(
         source_io,
         source_root,
         relative_path,
         source_path,
         source_before,
         destination_root,
         destination_path
       ) do
    case :file.open(destination_path, [:write, :binary, :raw, :exclusive, :nofollow]) do
      {:ok, destination_io} ->
        result =
          try do
            with {:ok, opened_destination} <- descriptor_stat(destination_io),
                 :ok <- require_regular(opened_destination),
                 {:ok, _bytes_copied} <- :file.copy(source_io, destination_io),
                 :ok <-
                   verify_source_after(
                     source_io,
                     source_root,
                     relative_path,
                     source_path,
                     source_before
                   ),
                 :ok <-
                   verify_destination_after(
                     destination_io,
                     destination_root,
                     relative_path,
                     destination_path,
                     opened_destination
                   ) do
              :ok
            end
          after
            _ = :file.close(destination_io)
          end

        if result != :ok do
          remove_owned_destination(
            destination_root,
            relative_path,
            destination_path
          )
        end

        result

      {:error, _reason} ->
        {:error, :destination_open_failed}
    end
  end

  defp verify_source_after(
         source_io,
         source_root,
         relative_path,
         source_path,
         source_before
       ) do
    with {:ok, after_read} <- descriptor_stat(source_io),
         :ok <- require_regular(after_read),
         :ok <- verify_file_stable(source_before, after_read),
         {:ok, source_after} <- File.lstat(source_path),
         :ok <- require_regular(source_after),
         :ok <- verify_file_stable(after_read, source_after),
         {:ok, ^source_path} <- Paths.safe_path(source_root, relative_path) do
      :ok
    else
      _reason -> {:error, :source_changed}
    end
  end

  defp verify_destination_after(
         destination_io,
         destination_root,
         relative_path,
         destination_path,
         opened_destination
       ) do
    with {:ok, after_write} <- descriptor_stat(destination_io),
         :ok <- require_regular(after_write),
         :ok <- verify_file_identity(opened_destination, after_write),
         {:ok, destination_after} <- File.lstat(destination_path),
         :ok <- require_regular(destination_after),
         :ok <- verify_file_identity(after_write, destination_after),
         {:ok, ^destination_path} <- Paths.safe_path(destination_root, relative_path) do
      :ok
    else
      _reason -> {:error, :destination_changed}
    end
  end

  defp remove_owned_destination(destination_root, relative_path, destination_path) do
    with {:ok, ^destination_path} <- Paths.safe_path(destination_root, relative_path),
         {:ok, %File.Stat{type: :regular}} <- File.lstat(destination_path) do
      File.rm(destination_path)
    else
      _reason -> :ok
    end
  end

  defp descriptor_stat(io) do
    case :file.read_file_info(io, time: :universal) do
      {:ok, info} -> {:ok, File.Stat.from_record(info)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_regular(%File.Stat{type: :regular}), do: :ok
  defp require_regular(%File.Stat{}), do: {:error, :not_regular}

  defp verify_file_identity(
         %File.Stat{
           inode: inode,
           major_device: major_device,
           minor_device: minor_device
         },
         %File.Stat{
           inode: inode,
           major_device: major_device,
           minor_device: minor_device
         }
       ),
       do: :ok

  defp verify_file_identity(%File.Stat{}, %File.Stat{}), do: {:error, :file_changed}

  defp verify_file_stable(
         %File.Stat{size: size, mtime: mtime, ctime: ctime} = before,
         %File.Stat{size: size, mtime: mtime, ctime: ctime} = after_stat
       ) do
    verify_file_identity(before, after_stat)
  end

  defp verify_file_stable(%File.Stat{}, %File.Stat{}), do: {:error, :file_changed}

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
