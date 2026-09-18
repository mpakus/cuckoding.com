defmodule Cuckoding.Knowledge.Store do
  @moduledoc "Owns confined knowledge paths and hash-verified content reads."

  alias Cuckoding.Knowledge.Item
  alias Cuckoding.Knowledge.Parser
  alias Cuckoding.Projects.Project
  alias Cuckoding.Repo

  @directories %{
    "facts" => "fact",
    "decisions" => "decision",
    "patterns" => "pattern",
    "recipes" => "recipe",
    "observations" => "observation"
  }
  @maximum_files 1_000

  def ensure_project_layout(%Project{} = project) do
    with {:ok, repo} <- canonical_directory(project.repo_path),
         root = Path.join(repo, ".cuckoding/knowledge"),
         :ok <- reject_symlink_components(root, repo),
         :ok <- create_layout(root),
         :ok <- reject_symlink_components(root, repo) do
      {:ok, root}
    end
  end

  def ensure_global_layout(options \\ []) do
    root = global_root(options)
    parent = Path.dirname(root)

    with :ok <- File.mkdir_p(parent),
         {:ok, parent} <- canonical_directory(parent),
         :ok <- reject_symlink_components(root, parent),
         :ok <- create_layout(root),
         :ok <- reject_symlink_components(root, parent) do
      {:ok, root}
    end
  end

  def project_root(%Project{} = project) do
    with {:ok, repo} <- canonical_directory(project.repo_path),
         root = Path.join(repo, ".cuckoding/knowledge"),
         :ok <- validate_optional_root(root, repo) do
      {:ok, root}
    end
  end

  def global_root(options \\ []) do
    Keyword.get_lazy(options, :global_root, fn ->
      database = Cuckoding.Repo.config()[:database] || "cuckoding.db"
      Path.join([Path.dirname(Path.expand(database)), "knowledge", "global"])
    end)
    |> Path.expand()
  end

  def scan(root) when is_binary(root) do
    case File.lstat(root) do
      {:ok, %{type: :directory}} -> scan_directories(root)
      {:ok, %{type: :symlink}} -> {:error, :knowledge_root_symlink}
      {:ok, _stat} -> {:error, :knowledge_root_not_directory}
      {:error, :enoent} -> {:ok, %{files: [], errors: [], seen: MapSet.new()}}
      {:error, reason} -> {:error, {:knowledge_root_unavailable, reason}}
    end
  end

  def expected_kind(relative_path) when is_binary(relative_path) do
    relative_path
    |> Path.split()
    |> case do
      [directory, filename] when is_map_key(@directories, directory) ->
        if Path.extname(filename) == ".md", do: {:ok, @directories[directory]}, else: :error

      _parts ->
        :error
    end
  end

  def read_for_project(project_id, item_id, options \\ [])

  def read_for_project(project_id, item_id, options)
      when is_binary(project_id) and is_binary(item_id) do
    if Repo.get(Project, project_id) do
      case Repo.get(Item, item_id) do
        %Item{scope: "project", project_id: ^project_id} = item -> read_project_item(item)
        %Item{scope: "global"} = item -> read_global_item(item, options)
        %Item{} -> {:error, :knowledge_scope_refused}
        nil -> {:error, :knowledge_item_not_found}
      end
    else
      {:error, :project_not_found}
    end
  end

  def read_for_project(_project_id, _item_id, _options),
    do: {:error, :invalid_knowledge_identity}

  def accept_user_edit(%Project{id: project_id} = project, item_id) when is_binary(item_id) do
    with %Item{scope: "project", project_id: ^project_id, sync_state: "modified"} = item <-
           Repo.get(Item, item_id),
         {:ok, root} <- project_root(project),
         {:ok, path} <- confined_file(root, item.file_path),
         {:ok, document} <- Parser.parse_file(path),
         :ok <- same_identity(document, item),
         :ok <- matching_kind(document, item.file_path),
         true <- document.metadata.version > item.version,
         {:ok, updated} <-
           item
           |> Item.user_revision_changeset(document_attrs(document))
           |> Repo.update() do
      {:ok, updated}
    else
      nil -> {:error, :knowledge_item_not_found}
      %Item{} -> {:error, :knowledge_item_not_modified}
      false -> {:error, :knowledge_version_must_increase}
      {:error, _reason} = error -> error
    end
  end

  def accept_user_edit(%Project{}, _item_id), do: {:error, :invalid_knowledge_identity}

  def file_hash(path) do
    with {:ok, %{type: :regular, size: size}} when size <= 1_048_576 <- File.lstat(path),
         {:ok, raw} <- File.read(path) do
      {:ok, sha256(raw)}
    else
      {:ok, _stat} -> {:error, :invalid_knowledge_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_layout(root) do
    [root | Enum.map(Map.keys(@directories), &Path.join(root, &1))]
    |> Enum.concat([Path.join(root, "skills")])
    |> Enum.reduce_while(:ok, fn path, :ok ->
      case File.mkdir_p(path) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:knowledge_layout_failed, reason}}}
      end
    end)
  end

  defp scan_directories(root) do
    {files, errors, seen} =
      Enum.reduce(@directories, {[], [], MapSet.new()}, fn {directory, _kind}, acc ->
        scan_directory(root, directory, acc)
      end)

    if length(files) > @maximum_files,
      do: {:error, :too_many_knowledge_files},
      else: {:ok, %{files: Enum.sort(files), errors: Enum.sort(errors), seen: seen}}
  end

  defp scan_directory(root, directory, {files, errors, seen}) do
    path = Path.join(root, directory)

    case File.lstat(path) do
      {:ok, %{type: :directory}} -> scan_names(root, path, directory, files, errors, seen)
      {:ok, %{type: :symlink}} -> {files, [{directory, :directory_symlink} | errors], seen}
      {:ok, _stat} -> {files, [{directory, :not_a_directory} | errors], seen}
      {:error, :enoent} -> {files, errors, seen}
      {:error, reason} -> {files, [{directory, reason} | errors], seen}
    end
  end

  defp scan_names(root, path, directory, files, errors, seen) do
    case File.ls(path) do
      {:ok, names} ->
        names
        |> Enum.filter(&(Path.extname(&1) == ".md"))
        |> Enum.sort()
        |> Enum.reduce({files, errors, seen}, fn name, acc ->
          scan_file(root, Path.join(directory, name), acc)
        end)

      {:error, reason} ->
        {files, [{directory, reason} | errors], seen}
    end
  end

  defp scan_file(root, relative, {files, errors, seen}) do
    path = Path.join(root, relative)
    seen = MapSet.put(seen, relative)

    case File.lstat(path) do
      {:ok, %{type: :regular}} -> {[{relative, path} | files], errors, seen}
      {:ok, %{type: :symlink}} -> {files, [{relative, :file_symlink} | errors], seen}
      {:ok, _stat} -> {files, [{relative, :not_a_regular_file} | errors], seen}
      {:error, reason} -> {files, [{relative, reason} | errors], seen}
    end
  end

  defp read_project_item(item) do
    with %Project{} = project <- Repo.get(Project, item.project_id),
         {:ok, root} <- project_root(project),
         do: verified_read(root, item)
  end

  defp read_global_item(item, options) do
    if Keyword.get(options, :include_global, false),
      do: verified_read(global_root(options), item),
      else: {:error, :global_knowledge_not_enabled}
  end

  defp verified_read(root, item) do
    with {:ok, path} <- confined_file(root, item.file_path),
         {:ok, document} <- Parser.parse_file(path),
         true <- document.hash == item.content_hash and item.sync_state == "synced" do
      {:ok, %{item: item, document: document}}
    else
      false -> {:error, :knowledge_content_hash_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp confined_file(root, relative) do
    with {:ok, _kind} <- expected_kind(relative),
         path = Path.expand(relative, root),
         true <- String.starts_with?(path, Path.expand(root) <> "/") do
      {:ok, path}
    else
      :error -> {:error, :invalid_knowledge_file_path}
      false -> {:error, :knowledge_path_escape}
    end
  end

  defp same_identity(document, item) do
    cond do
      document.metadata.id != item.id -> {:error, :knowledge_identity_changed}
      document.metadata.scope != item.scope -> {:error, :knowledge_scope_changed}
      true -> :ok
    end
  end

  defp matching_kind(document, relative) do
    case expected_kind(relative) do
      {:ok, kind} when kind == document.metadata.kind -> :ok
      _other -> {:error, :knowledge_kind_path_mismatch}
    end
  end

  defp document_attrs(document) do
    Map.merge(document.metadata, %{
      content_hash: document.hash,
      observed_hash: document.hash
    })
  end

  defp validate_optional_root(root, base) do
    with :ok <- reject_symlink_components(root, base) do
      case File.lstat(root) do
        {:ok, %{type: :directory}} -> confined_directory(root, base)
        {:ok, %{type: :symlink}} -> {:error, :knowledge_root_symlink}
        {:ok, _stat} -> {:error, :knowledge_root_not_directory}
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, {:knowledge_root_unavailable, reason}}
      end
    end
  end

  defp reject_symlink_components(path, base) do
    path
    |> Path.relative_to(base)
    |> Path.split()
    |> Enum.reduce_while(base, fn component, parent ->
      current = Path.join(parent, component)

      case File.lstat(current) do
        {:ok, %{type: :symlink}} -> {:halt, {:error, :knowledge_path_symlink}}
        {:ok, _stat} -> {:cont, current}
        {:error, :enoent} -> {:cont, current}
        {:error, reason} -> {:halt, {:error, {:knowledge_path_unavailable, reason}}}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      _path -> :ok
    end
  end

  defp confined_directory(path, root) do
    with {:ok, resolved_root} <- canonical_directory(root),
         {:ok, resolved_path} <- canonical_directory(path),
         relative = Path.relative_to(resolved_path, resolved_root),
         false <- relative == ".." or String.starts_with?(relative, "../") do
      :ok
    else
      true -> {:error, :knowledge_path_escape}
      {:error, _reason} = error -> error
    end
  end

  defp canonical_directory(path) do
    expanded = Path.expand(path)

    case File.stat(expanded) do
      {:ok, %{type: :directory}} ->
        case System.cmd("/bin/pwd", ["-P"], cd: expanded, stderr_to_stdout: true) do
          {resolved, 0} -> {:ok, String.trim(resolved)}
          {_output, _status} -> {:error, :knowledge_path_resolution_failed}
        end

      {:ok, _stat} ->
        {:error, :knowledge_path_not_directory}

      {:error, reason} ->
        {:error, {:knowledge_path_unavailable, reason}}
    end
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
