defmodule AgentDesk.A2A.ArtifactFile do
  @moduledoc false

  alias AgentDesk.A2A.Artifact
  alias AgentDesk.Agents.Session
  alias AgentDesk.Paths
  alias AgentDesk.Projects.Project
  alias AgentDesk.Repo
  alias AgentDesk.Scope
  alias AgentDesk.Storage
  alias AgentDesk.Worktrees
  alias AgentDesk.Worktrees.Worktree

  @max_size_bytes 1_000_000

  @spec validate_publication(Scope.t(), Path.t(), non_neg_integer(), String.t()) ::
          {:ok, %{path: String.t(), sha256: String.t(), size_bytes: non_neg_integer()}}
          | {:error, term()}
  def validate_publication(
        %Scope{project: %Project{} = project, agent_session: %Session{} = session},
        path,
        claimed_size,
        claimed_sha256
      ) do
    with :ok <- same_project(project, session),
         {:ok, canonical_path, bytes} <- read_owned_bounded(project, session, path),
         :ok <- verify_size(bytes, claimed_size),
         {:ok, sha256} <- verify_hash(bytes, claimed_sha256) do
      {:ok, %{path: canonical_path, sha256: sha256, size_bytes: byte_size(bytes)}}
    end
  end

  def validate_publication(%Scope{}, _path, _claimed_size, _claimed_sha256),
    do: {:error, :artifact_owner_required}

  @spec validate_read(Scope.t(), Artifact.t()) :: :ok | {:error, term()}
  def validate_read(
        %Scope{project: %Project{id: project_id} = project},
        %Artifact{project_id: project_id, agent_session_id: session_id} = artifact
      )
      when is_binary(session_id) do
    with {:ok, canonical_path, bytes} <-
           read_owned_bounded(
             project,
             owner_session(project, session_id),
             artifact.path
           ),
         true <- canonical_path == artifact.path || {:error, :artifact_path_forbidden},
         :ok <- verify_size(bytes, artifact.size_bytes),
         {:ok, _sha256} <- verify_hash(bytes, artifact.sha256) do
      :ok
    end
  end

  def validate_read(%Scope{}, %Artifact{}), do: {:error, :artifact_path_forbidden}

  defp same_project(%Project{id: project_id}, %Session{project_id: project_id}), do: :ok
  defp same_project(%Project{}, %Session{}), do: {:error, :forbidden}

  defp owner_session(%Project{id: project_id}, session_id) do
    Repo.get_by(Session, id: session_id, project_id: project_id)
  end

  defp owned_path(%Project{} = project, %Session{} = session, path) when is_binary(path) do
    roots = allowed_roots(project, session)

    if Path.type(path) == :absolute do
      safe_under_any(roots, path)
    else
      case checkout_root(project, session) do
        nil -> {:error, :artifact_path_forbidden}
        root -> translate_path_result(Paths.safe_path(root, path))
      end
    end
  end

  defp owned_path(%Project{}, %Session{}, _path), do: {:error, :artifact_path_forbidden}

  defp allowed_roots(%Project{} = project, %Session{} = session) do
    [
      checkout_root(project, session),
      Storage.session_dir(project.id, session.id)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp checkout_root(%Project{} = project, %Session{} = session) do
    case Worktrees.get_for_session(session.id) do
      %Worktree{project_id: project_id, path: path} when project_id == project.id ->
        path

      nil ->
        if Worktrees.shared_mode?() or Worktrees.shared_session?(session) do
          project.canonical_path
        end
    end
  end

  defp safe_under_any(roots, path) do
    Enum.reduce_while(roots, {:error, :artifact_path_forbidden}, fn root, _acc ->
      case Paths.safe_path(root, path) do
        {:ok, canonical} -> {:halt, {:ok, canonical}}
        {:error, _reason} -> {:cont, {:error, :artifact_path_forbidden}}
      end
    end)
  end

  defp translate_path_result({:ok, canonical}), do: {:ok, canonical}
  defp translate_path_result({:error, _reason}), do: {:error, :artifact_path_forbidden}

  defp read_owned_bounded(%Project{} = project, %Session{} = session, path) do
    with {:ok, canonical_before} <- owned_path(project, session, path),
         {:ok, bytes} <- read_bounded_regular(canonical_before),
         {:ok, canonical_after} <- owned_path(project, session, path),
         true <-
           canonical_before == canonical_after || {:error, :artifact_file_changed} do
      {:ok, canonical_before, bytes}
    end
  end

  defp read_owned_bounded(%Project{}, nil, _path),
    do: {:error, :artifact_path_forbidden}

  defp read_bounded_regular(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular} = before_open} ->
        with_open_file(path, fn io ->
          read_stable_file(io, path, before_open)
        end)

      {:ok, _stat} ->
        {:error, :artifact_not_regular}

      {:error, :enoent} ->
        {:error, :missing_bytes}

      {:error, _reason} ->
        {:error, :missing_bytes}
    end
  end

  defp with_open_file(path, fun) do
    case :file.open(path, [:read, :binary, :raw]) do
      {:ok, io} ->
        try do
          fun.(io)
        after
          _ = :file.close(io)
        end

      {:error, :enoent} ->
        {:error, :missing_bytes}

      {:error, _reason} ->
        {:error, :missing_bytes}
    end
  end

  defp read_stable_file(io, path, before_open) do
    with {:ok, opened} <- descriptor_stat(io),
         :ok <- require_regular(opened),
         :ok <- verify_identity(before_open, opened),
         {:ok, bytes} <- bounded_read(io),
         {:ok, after_read} <- descriptor_stat(io),
         :ok <- require_regular(after_read),
         :ok <- verify_stable_descriptor(opened, after_read),
         {:ok, after_path} <- File.lstat(path),
         :ok <- require_regular(after_path),
         :ok <- verify_identity(after_read, after_path),
         :ok <- verify_stable_metadata(after_read, after_path) do
      {:ok, bytes}
    else
      {:error, :too_large} -> {:error, :artifact_too_large}
      {:error, :enoent} -> {:error, :missing_bytes}
      {:error, _reason} = error -> error
    end
  end

  defp descriptor_stat(io) do
    case :file.read_file_info(io, time: :universal) do
      {:ok, info} -> {:ok, File.Stat.from_record(info)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp bounded_read(io) do
    case :file.read(io, @max_size_bytes + 1) do
      :eof ->
        {:ok, <<>>}

      {:ok, bytes} when is_binary(bytes) and byte_size(bytes) <= @max_size_bytes ->
        {:ok, bytes}

      {:ok, bytes} when is_binary(bytes) ->
        {:error, :too_large}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_regular(%File.Stat{type: :regular}), do: :ok
  defp require_regular(%File.Stat{}), do: {:error, :artifact_not_regular}

  defp verify_identity(
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

  defp verify_identity(%File.Stat{}, %File.Stat{}),
    do: {:error, :artifact_file_changed}

  defp verify_stable_descriptor(before_read, after_read) do
    with :ok <- verify_identity(before_read, after_read),
         :ok <- verify_stable_metadata(before_read, after_read) do
      :ok
    end
  end

  defp verify_stable_metadata(
         %File.Stat{size: size, mtime: mtime, ctime: ctime},
         %File.Stat{size: size, mtime: mtime, ctime: ctime}
       ),
       do: :ok

  defp verify_stable_metadata(%File.Stat{}, %File.Stat{}),
    do: {:error, :artifact_file_changed}

  defp verify_size(bytes, claimed_size) when byte_size(bytes) == claimed_size, do: :ok
  defp verify_size(_bytes, _claimed_size), do: {:error, :artifact_size_mismatch}

  defp verify_hash(bytes, claimed_sha256) do
    sha256 = :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)

    if sha256 == claimed_sha256,
      do: {:ok, sha256},
      else: {:error, :artifact_integrity}
  end
end
