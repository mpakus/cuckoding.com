defmodule AgentDesk.Paths do
  @moduledoc """
  Path canonicalization used before comparing or persisting filesystem locations.
  """

  @max_symlink_depth 32

  @type path_error ::
          :invalid_path | :not_found | :not_a_directory | :outside_root | :symlink_loop

  @type read_error ::
          path_error()
          | :not_regular
          | :file_changed
          | :too_large
          | {:file_error, File.posix()}

  @spec canonicalize(Path.t()) :: {:ok, String.t()} | {:error, path_error()}
  def canonicalize(path) when is_binary(path) do
    with :ok <- validate(path),
         {:ok, resolved} <- resolve_path(path, 0),
         :ok <- require_directory(resolved) do
      {:ok, resolved}
    end
  end

  @doc """
  True when `path` is inside `root` after expansion and symlink resolution.
  """
  @spec within?(Path.t(), Path.t()) :: boolean()
  def within?(root, path) when is_binary(root) and is_binary(path) do
    match?({:ok, _path}, safe_path(root, path))
  end

  @doc """
  Returns a canonical path inside `root`.

  Relative paths are resolved from `root`. Every existing component is checked
  for symlinks, while a non-existing suffix remains normalized under its
  canonical existing ancestor.
  """
  @spec safe_path(Path.t(), Path.t()) :: {:ok, String.t()} | {:error, path_error()}
  def safe_path(root, path) when is_binary(root) and is_binary(path) do
    with :ok <- validate(path),
         {:ok, canonical_root} <- canonicalize(root),
         candidate <- expand_from_root(canonical_root, path),
         {:ok, canonical_candidate} <- resolve_path(candidate, 0),
         true <- contained?(canonical_root, canonical_candidate) do
      {:ok, canonical_candidate}
    else
      false -> {:error, :outside_root}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reads a regular file under `root` without following the final path component.

  The read is capped at `max_bytes` and verifies the descriptor, inode,
  metadata, requested path, and canonical path before returning bytes.
  """
  @spec read_bounded_regular(Path.t(), Path.t(), pos_integer(), keyword()) ::
          {:ok, String.t(), binary()} | {:error, read_error()}
  def read_bounded_regular(root, path, max_bytes, opts \\ [])

  def read_bounded_regular(root, path, max_bytes, opts)
      when is_binary(root) and is_binary(path) and is_integer(max_bytes) and max_bytes > 0 and
             is_list(opts) do
    with {:ok, canonical_before} <- safe_path(root, path),
         {:ok, requested_path} <- requested_path(root, path),
         {:ok, requested_before} <- lstat_regular(requested_path),
         {:ok, canonical_before_stat} <- lstat_regular(canonical_before),
         :ok <- verify_identity(requested_before, canonical_before_stat),
         :ok <- notify_phase(opts, :validated),
         {:ok, bytes} <-
           with_open_file(canonical_before, fn io ->
             read_stable_file(
               io,
               root,
               path,
               requested_path,
               canonical_before,
               canonical_before_stat,
               max_bytes,
               opts
             )
           end) do
      {:ok, canonical_before, bytes}
    end
  end

  def read_bounded_regular(_root, _path, _max_bytes, _opts), do: {:error, :invalid_path}

  defp validate(path) do
    if String.valid?(path) and :binary.match(path, <<0>>) == :nomatch do
      :ok
    else
      {:error, :invalid_path}
    end
  end

  defp expand_from_root(root, path) do
    if Path.type(path) == :absolute, do: Path.expand(path), else: Path.expand(path, root)
  end

  defp requested_path(root, path) do
    with {:ok, canonical_root} <- canonicalize(root) do
      {:ok, expand_from_root(canonical_root, path)}
    end
  end

  defp resolve_path(_path, depth) when depth > @max_symlink_depth,
    do: {:error, :symlink_loop}

  defp resolve_path(path, depth) do
    path
    |> Path.expand()
    |> Path.split()
    |> then(fn [root | components] -> resolve_components(root, components, depth) end)
  end

  defp resolve_components(current, [], _depth), do: {:ok, Path.expand(current)}

  defp resolve_components(current, [component | rest], depth) do
    next = Path.join(current, component)

    case File.lstat(next) do
      {:ok, %{type: :symlink}} ->
        case File.read_link(next) do
          {:ok, target} ->
            target
            |> expand_target(next)
            |> append_components(rest)
            |> resolve_path(depth + 1)

          {:error, :enoent} ->
            {:error, :not_found}

          {:error, _reason} ->
            {:error, :not_found}
        end

      {:ok, _stat} ->
        resolve_components(next, rest, depth)

      {:error, :enoent} ->
        {:ok, append_components(next, rest)}

      {:error, _reason} ->
        {:error, :not_found}
    end
  end

  defp append_components(path, components) do
    Enum.reduce(components, path, &Path.join(&2, &1))
  end

  defp require_directory(path) do
    case File.stat(path) do
      {:ok, %{type: :directory}} -> :ok
      {:ok, _stat} -> {:error, :not_a_directory}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  defp contained?("/", candidate), do: String.starts_with?(candidate, "/")

  defp contained?(root, candidate) do
    candidate == root or String.starts_with?(candidate, root <> "/")
  end

  defp expand_target(target, from_path) do
    if Path.type(target) == :absolute do
      Path.expand(target)
    else
      Path.expand(target, Path.dirname(from_path))
    end
  end

  defp lstat_regular(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular} = stat} -> {:ok, stat}
      {:ok, %File.Stat{}} -> {:error, :not_regular}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, {:file_error, reason}}
    end
  end

  defp with_open_file(path, fun) do
    case :file.open(path, [:read, :binary, :raw, :nofollow, :nonblock]) do
      {:ok, io} ->
        try do
          fun.(io)
        after
          _ = :file.close(io)
        end

      {:error, reason} when reason in [:enoent, :eloop, :eagain, :enxio] ->
        {:error, :file_changed}

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  defp read_stable_file(
         io,
         root,
         path,
         requested_path,
         canonical_path,
         before_open,
         max_bytes,
         opts
       ) do
    with {:ok, opened} <- descriptor_stat(io),
         :ok <- require_regular(opened, :file_changed),
         :ok <- verify_identity(before_open, opened),
         :ok <- notify_phase(opts, :opened),
         {:ok, bytes} <- bounded_read(io, max_bytes),
         :ok <- notify_phase(opts, :read),
         {:ok, after_read} <- descriptor_stat(io),
         :ok <- require_regular(after_read, :file_changed),
         :ok <- verify_stable_descriptor(opened, after_read),
         :ok <-
           verify_paths_after(
             root,
             path,
             requested_path,
             canonical_path,
             after_read
           ) do
      {:ok, bytes}
    end
  end

  defp descriptor_stat(io) do
    case :file.read_file_info(io, time: :universal) do
      {:ok, info} -> {:ok, File.Stat.from_record(info)}
      {:error, reason} -> {:error, {:file_error, reason}}
    end
  end

  defp bounded_read(io, max_bytes), do: bounded_read(io, max_bytes, 0, [])

  defp bounded_read(_io, max_bytes, total, _chunks) when total > max_bytes,
    do: {:error, :too_large}

  defp bounded_read(io, max_bytes, total, chunks) do
    read_size = min(64 * 1024, max_bytes + 1 - total)

    case :file.read(io, read_size) do
      :eof ->
        {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

      {:ok, bytes} when is_binary(bytes) ->
        bounded_read(io, max_bytes, total + byte_size(bytes), [bytes | chunks])

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  defp verify_paths_after(root, path, requested_path, canonical_path, after_read) do
    with {:ok, canonical_after_stat} <- lstat_regular(canonical_path),
         :ok <- verify_identity(after_read, canonical_after_stat),
         :ok <- verify_stable_metadata(after_read, canonical_after_stat),
         {:ok, requested_after} <- lstat_regular(requested_path),
         :ok <- verify_identity(after_read, requested_after),
         :ok <- verify_stable_metadata(after_read, requested_after),
         {:ok, ^canonical_path} <- safe_path(root, path) do
      :ok
    else
      _reason -> {:error, :file_changed}
    end
  end

  defp require_regular(%File.Stat{type: :regular}, _error), do: :ok
  defp require_regular(%File.Stat{}, error), do: {:error, error}

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

  defp verify_identity(%File.Stat{}, %File.Stat{}), do: {:error, :file_changed}

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

  defp verify_stable_metadata(%File.Stat{}, %File.Stat{}), do: {:error, :file_changed}

  defp notify_phase(opts, phase) do
    case Keyword.get(opts, :on_phase) do
      callback when is_function(callback, 1) ->
        callback.(phase)
        :ok

      _other ->
        :ok
    end
  end
end
