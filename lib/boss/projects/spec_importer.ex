defmodule Boss.Projects.SpecImporter do
  @moduledoc "Bounded full-directory import. A failed scan never replaces the persisted snapshot."
  import Ecto.Query
  alias Boss.{Projects, Repo}
  alias Boss.Projects.{Project, Repository, Spec, SpecDocument}
  require Logger

  @timeout 10_000
  @file_bytes 1_048_576
  @total_bytes 8_388_608

  def sync(project_id) do
    parent = self()
    ref = make_ref()
    repo = Repo.get_dynamic_repo()
    repo = if is_atom(repo), do: Process.whereis(repo), else: repo

    case Task.Supervisor.start_child(Boss.SpecImportSupervisor, fn ->
           Process.flag(:max_heap_size, %{size: 8_000_000, kill: true, error_logger: false})
           Repo.put_dynamic_repo(repo)
           {:ok, timer} = :timer.kill_after(@timeout, self())

           try do
             result = Repo.transaction(fn -> scan_and_apply(project_id) end, mode: :immediate)
             send(parent, {ref, result})
           rescue
             error ->
               Logger.warning("Spec sync failed (#{inspect(error.__struct__)})")
               send(parent, {ref, {:error, errors(".", "Sync could not complete. Try again.")}})
           after
             :timer.cancel(timer)
           end
         end) do
      {:ok, pid} -> await_result(pid, ref)
      {:error, :max_children} -> {:error, errors(".", "Sync is busy. Try again shortly.")}
      {:error, _} -> {:error, errors(".", "Sync is unavailable. Try again.")}
    end
  end

  defp await_result(pid, ref) do
    monitor = Process.monitor(pid)

    receive do
      {^ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^pid, _} ->
        {:error, errors(".", "Sync was interrupted. Refresh to check the current specs.")}
    after
      @timeout + 1000 ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor, [:flush])
        {:error, errors(".", "Sync timed out. Refresh to check the current specs.")}
    end
  end

  defp scan_and_apply(project_id) do
    project = Repo.get(Project, project_id) || fail(".", "Project not found.")
    validate_root(project)
    state = walk(project, "", 0, %{entries: 0, bytes: 0, files: [], keys: MapSet.new()})
    validate_root(project)
    now = DateTime.utc_now()

    Repo.update_all(from(s in Spec, where: s.project_id == ^project_id and not s.missing),
      set: [missing: true, updated_at: now]
    )

    counts =
      Enum.reduce(Enum.reverse(state.files), %{created: 0, revised: 0, unchanged: 0}, fn {attrs,
                                                                                          input},
                                                                                         counts ->
        if spec = Repo.get_by(Spec, project_id: project_id, identity_key: input.identity_key) do
          spec
          |> Ecto.Changeset.change(relative_path: input.relative_path, missing: false)
          |> Repo.update!()
        end

        case Projects.record_spec(project_id, attrs) do
          {:ok, %{change: change}} -> Map.update!(counts, change, &(&1 + 1))
          {:error, changeset} -> fail(attrs.relative_path, changeset_message(changeset))
        end
      end)

    missing =
      Repo.aggregate(from(s in Spec, where: s.project_id == ^project_id and s.missing), :count)

    Map.put(counts, :missing, missing)
  end

  defp walk(project, relative, depth, state) do
    if depth > 16, do: fail(relative, "Specs exceed the maximum directory depth of 16.")
    path = Path.join(project.specs_path, relative)
    before = lstat(path, relative)
    if before.type != :directory, do: fail(relative, "Expected a directory without symlinks.")

    names =
      case File.ls(path) do
        {:ok, names} -> Enum.sort(names)
        {:error, reason} -> fail(relative, to_string(:file.format_error(reason)))
      end

    state = %{state | entries: state.entries + length(names)}

    if state.entries > 1000,
      do: fail(relative, "Specs exceed the limit of 1000 directory entries.")

    state =
      Enum.reduce(names, state, fn name, state ->
        child = if relative == "", do: name, else: Path.join(relative, name)
        absolute = Path.join(project.specs_path, child)
        stat = lstat(absolute, child)

        case stat.type do
          :directory ->
            walk(project, child, depth + 1, state)

          :regular ->
            if String.downcase(Path.extname(name)) == ".md",
              do: read_spec(project, child, stat, state),
              else: state

          _ ->
            fail(child, "Specs cannot contain symlinks or special files.")
        end
      end)

    if fingerprint(before) != fingerprint(lstat(path, relative)),
      do: fail(relative, "Directory changed during sync. Try again.")

    state
  end

  defp read_spec(project, relative, before, state) do
    if length(state.files) >= 256,
      do: fail(relative, "Specs exceed the limit of 256 Markdown files.")

    if before.size > @file_bytes, do: fail(relative, "Spec exceeds the limit of 1 MiB.")
    path = Path.join(project.specs_path, relative)
    validate_parent(project, path, relative)

    result =
      File.open(path, [:read, :binary, :raw], fn file ->
        if fingerprint(before) != fingerprint(fstat(file, relative)),
          do: fail(relative, "File changed during sync. Try again.")

        text =
          case :file.read(file, @file_bytes + 1) do
            {:ok, text} -> text
            :eof -> ""
            {:error, reason} -> fail(relative, to_string(:file.format_error(reason)))
          end

        if byte_size(text) > @file_bytes, do: fail(relative, "Spec exceeds the limit of 1 MiB.")
        validate_parent(project, path, relative)

        if fingerprint(before) != fingerprint(fstat(file, relative)) or
             fingerprint(before) != fingerprint(lstat(path, relative)),
           do: fail(relative, "File changed during sync. Try again.")

        text
      end)

    text =
      case result do
        {:ok, text} -> text
        {:error, reason} -> fail(relative, to_string(:file.format_error(reason)))
      end

    bytes = state.bytes + byte_size(text)
    if bytes > @total_bytes, do: fail(relative, "Specs exceed the total size limit of 8 MiB.")

    attrs =
      case SpecDocument.parse(relative, text) do
        {:ok, attrs} -> attrs
        {:error, message} -> fail(relative, message)
      end

    input =
      case Spec.changeset(project.id, attrs) |> Ecto.Changeset.apply_action(:insert) do
        {:ok, input} -> input
        {:error, changeset} -> fail(relative, changeset_message(changeset))
      end

    if MapSet.member?(state.keys, input.identity_key),
      do: fail(relative, "Duplicate spec ID in this scan.")

    %{
      state
      | bytes: bytes,
        files: [{attrs, input} | state.files],
        keys: MapSet.put(state.keys, input.identity_key)
    }
  end

  defp validate_root(project) do
    root = lstat(project.root_path, ".")
    if root.type != :directory, do: fail(".", "Repository folder is unavailable or is a symlink.")

    case Repository.specs_directory(project.root_path, project.specs_path) do
      {:ok, _} -> :ok
      {:error, _} -> fail(".", "Specs folder is missing, inaccessible or contains a symlink.")
    end
  end

  defp validate_parent(project, path, relative) do
    case Repository.specs_directory(project.root_path, Path.dirname(path)) do
      {:ok, _} -> :ok
      {:error, _} -> fail(relative, "Parent directory changed or contains a symlink.")
    end
  end

  defp lstat(path, relative) do
    case File.lstat(path, time: :posix) do
      {:ok, stat} -> stat
      {:error, reason} -> fail(relative, to_string(:file.format_error(reason)))
    end
  end

  defp fstat(file, relative) do
    case :file.read_file_info(file, time: :posix) do
      {:ok, record} -> File.Stat.from_record(record)
      {:error, reason} -> fail(relative, to_string(:file.format_error(reason)))
    end
  end

  defp fingerprint(stat),
    do:
      {stat.type, stat.inode, stat.major_device, stat.minor_device, stat.size, stat.mtime,
       stat.ctime}

  defp changeset_message(changeset),
    do:
      Enum.map_join(changeset.errors, "; ", fn {field, {message, _}} -> "#{field} #{message}" end)

  defp errors(path, message), do: [%{path: if(path == "", do: ".", else: path), message: message}]
  defp fail(path, message), do: Repo.rollback(errors(path, message))
end
