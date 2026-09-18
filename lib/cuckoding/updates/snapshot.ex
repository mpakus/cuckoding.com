defmodule Cuckoding.Updates.Snapshot do
  @moduledoc "Creates and restores hash-verified update snapshots without following symlinks."

  import Ecto.Query

  alias Cuckoding.Knowledge.Store
  alias Cuckoding.Projects.Project
  alias Cuckoding.Repo

  @manifest "manifest.json"

  def create(id, metadata, options \\ []) when is_binary(id) and is_map(metadata) do
    database = database_path(options)

    backup_root =
      Keyword.get(
        options,
        :backup_root,
        Application.get_env(:cuckoding, :update_backup_root, default_backup_root(database))
      )

    directory = Path.join(backup_root, id)

    with :ok <- fresh_directory(directory),
         {:ok, database_entry} <- backup_database(database, directory, options),
         {:ok, file_entries} <- backup_files(directory, sources(options)),
         manifest = %{
           "version" => 1,
           "metadata" => metadata,
           "files" => [database_entry | file_entries]
         },
         encoded = Jason.encode!(manifest, pretty: true) <> "\n",
         :ok <- write_private(Path.join(directory, @manifest), encoded) do
      {:ok,
       %{
         path: directory,
         manifest_hash: sha256(encoded),
         files: length(manifest["files"])
       }}
    else
      {:error, reason} ->
        File.rm_rf(directory)
        {:error, {:snapshot_failed, reason}}
    end
  end

  def restore(directory, expected_hash, options \\ [])
      when is_binary(directory) and is_binary(expected_hash) do
    manifest_path = Path.join(directory, @manifest)

    with {:ok, %{type: :regular}} <- File.lstat(manifest_path),
         {:ok, encoded} <- File.read(manifest_path),
         true <- secure_equal?(sha256(encoded), expected_hash),
         {:ok, manifest} <- Jason.decode(encoded),
         true <- manifest["version"] == 1,
         :ok <- validate_entries(manifest["files"], directory, options),
         :ok <- preserve_failed_database(directory, options),
         :ok <- restore_entries(manifest["files"], directory) do
      :ok
    else
      false -> {:error, :snapshot_manifest_mismatch}
      {:error, reason} -> {:error, {:snapshot_restore_failed, reason}}
      _other -> {:error, :invalid_snapshot_manifest}
    end
  end

  defp fresh_directory(directory) do
    with :ok <- File.mkdir_p(Path.dirname(directory)),
         {:error, :enoent} <- File.lstat(directory),
         :ok <- File.mkdir(directory),
         :ok <- File.chmod(directory, 0o700) do
      :ok
    else
      {:ok, _stat} -> {:error, :snapshot_exists}
      {:error, reason} -> {:error, reason}
    end
  end

  defp backup_database(source, directory, options) do
    destination = Path.join(directory, "database.sqlite3")
    backup = Keyword.get(options, :database_backup, &vacuum_into/2)

    with :ok <- backup.(source, destination),
         :ok <- File.chmod(destination, 0o600) do
      {:ok, entry("database", source, "database.sqlite3", destination)}
    end
  end

  defp vacuum_into(_source, destination) do
    case Ecto.Adapters.SQL.query(Repo, "VACUUM INTO ?", [destination], timeout: :infinity) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp backup_files(directory, sources) do
    Enum.reduce_while(sources, {:ok, []}, fn {kind, label, source}, {:ok, entries} ->
      case backup_source(directory, kind, label, source) do
        {:ok, copied} -> {:cont, {:ok, entries ++ copied}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp backup_source(directory, kind, label, source) do
    case File.lstat(source) do
      {:ok, %{type: :directory}} ->
        copy_tree(source, Path.join([directory, kind, label]), kind, directory)

      {:ok, %{type: :regular}} ->
        copy_file(source, directory, kind, label)

      {:error, :enoent} ->
        {:ok, []}

      {:ok, _stat} ->
        {:error, {:unsafe_snapshot_source, source}}

      {:error, reason} ->
        {:error, {source, reason}}
    end
  end

  defp copy_file(source, directory, kind, label) do
    relative = Path.join([kind, label, Path.basename(source)])
    destination = Path.join(directory, relative)

    with :ok <- File.mkdir_p(Path.dirname(destination)),
         :ok <- File.cp(source, destination),
         :ok <- File.chmod(destination, 0o600) do
      {:ok, [entry(kind, source, relative, destination)]}
    end
  end

  defp copy_tree(source, destination, kind, backup_root) do
    with :ok <- File.mkdir_p(destination),
         :ok <- File.chmod(destination, 0o700),
         {:ok, names} <- File.ls(source) do
      copy_names(Enum.sort(names), source, destination, kind, backup_root)
    end
  end

  defp copy_names(names, source, destination, kind, backup_root) do
    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, entries} ->
      case copy_tree_entry(source, destination, name, kind, backup_root) do
        {:ok, copied} -> {:cont, {:ok, entries ++ copied}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp copy_tree_entry(source, destination, name, kind, backup_root) do
    from = Path.join(source, name)
    to = Path.join(destination, name)

    case File.lstat(from) do
      {:ok, %{type: :directory}} ->
        copy_tree(from, to, kind, backup_root)

      {:ok, %{type: :regular}} ->
        copy_tree_file(from, to, kind, backup_root)

      {:ok, _stat} ->
        {:error, {:unsafe_snapshot_source, from}}

      {:error, reason} ->
        {:error, {from, reason}}
    end
  end

  defp copy_tree_file(from, to, kind, backup_root) do
    with :ok <- File.cp(from, to),
         :ok <- File.chmod(to, 0o600) do
      {:ok, [entry(kind, from, Path.relative_to(to, backup_root), to)]}
    end
  end

  defp entry(kind, source, relative, backup) do
    %{
      "kind" => kind,
      "source" => Path.expand(source),
      "backup" => relative,
      "sha256" => backup |> File.read!() |> sha256()
    }
  end

  defp validate_entries(entries, directory, options) when is_list(entries) do
    allowed = allowed_sources(options, entries)

    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      backup = Path.expand(Path.join(directory, entry["backup"] || ""))
      source = Path.expand(entry["source"] || "")

      result =
        with true <- confined?(backup, directory),
             true <- allowed?(source, allowed),
             {:ok, %{type: :regular}} <- File.lstat(backup),
             {:ok, contents} <- File.read(backup),
             true <- secure_equal?(sha256(contents), entry["sha256"] || "") do
          :ok
        else
          _other -> {:error, :invalid_snapshot_entry}
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_entries(_entries, _directory, _options), do: {:error, :invalid_snapshot_entries}

  defp preserve_failed_database(directory, options) do
    database = database_path(options)

    case File.lstat(database) do
      {:ok, %{type: :regular}} ->
        File.cp(database, Path.join(directory, "failed-current.sqlite3"))

      {:error, :enoent} ->
        :ok

      {:ok, _stat} ->
        {:error, :unsafe_database_target}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp restore_entries(entries, directory) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      source = entry["source"]
      backup = Path.join(directory, entry["backup"])

      with :ok <- safe_target?(source),
           :ok <- File.mkdir_p(Path.dirname(source)),
           :ok <- atomic_copy(backup, source) do
        {:cont, :ok}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp safe_target?(path) do
    with :ok <- reject_symlink_parents(Path.dirname(path)) do
      case File.lstat(path) do
        {:ok, %{type: :regular}} -> :ok
        {:error, :enoent} -> :ok
        {:ok, _stat} -> {:error, :unsafe_restore_target}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp reject_symlink_parents("/"), do: :ok

  defp reject_symlink_parents(path) do
    with :ok <- reject_symlink_parents(Path.dirname(path)) do
      case File.lstat(path) do
        {:ok, %{type: :directory}} -> :ok
        {:error, :enoent} -> :ok
        {:ok, _stat} -> {:error, :unsafe_restore_parent}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp atomic_copy(source, destination) do
    temporary = destination <> ".restore-#{System.unique_integer([:positive])}"

    with :ok <- File.cp(source, temporary),
         :ok <- File.chmod(temporary, 0o600),
         :ok <- File.rename(temporary, destination) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(temporary)
        error
    end
  end

  defp write_private(path, contents) do
    with :ok <- File.write(path, contents, [:binary, :exclusive]) do
      File.chmod(path, 0o600)
    end
  end

  defp sources(options) do
    Keyword.get_lazy(options, :sources, fn ->
      project_sources() ++ [{"knowledge", "global", Store.global_root()}]
    end)
  end

  defp project_sources do
    Repo.all(from(project in Project, order_by: project.id))
    |> Enum.flat_map(fn project ->
      [
        {"knowledge", project.id, Path.join(project.repo_path, ".cuckoding/knowledge")},
        {"configuration", project.id, Path.join(project.repo_path, ".cuckoding/project.yml")}
      ]
    end)
  end

  defp allowed_sources(options, entries) do
    case Keyword.fetch(options, :allowed_sources) do
      {:ok, paths} -> %{exact: Enum.map(paths, &Path.expand/1)}
      :error -> %{exact: Enum.map(entries, &Path.expand(&1["source"] || ""))}
    end
  end

  defp allowed?(source, %{exact: paths}), do: source in paths

  defp confined?(path, root) do
    relative = Path.relative_to(Path.expand(path), Path.expand(root))
    relative != ".." and not String.starts_with?(relative, "../")
  end

  defp database_path(options),
    do: options |> Keyword.get(:database, Repo.config()[:database]) |> Path.expand()

  defp default_backup_root(database), do: Path.join(Path.dirname(database), "backups")

  defp sha256(contents), do: :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)

  defp secure_equal?(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_equal?(_left, _right), do: false
end
