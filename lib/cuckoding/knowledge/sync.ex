defmodule Cuckoding.Knowledge.Sync do
  @moduledoc "Synchronizes validated Markdown front matter into the SQLite knowledge index."

  import Ecto.Query

  alias Cuckoding.Knowledge.Item
  alias Cuckoding.Knowledge.Parser
  alias Cuckoding.Knowledge.Store
  alias Cuckoding.Projects.Project
  alias Cuckoding.Repo

  def run_project(%Project{} = project) do
    with {:ok, root} <- Store.project_root(project) do
      run("project", project.id, root)
    end
  end

  def run_global(options \\ []) do
    run("global", nil, Store.global_root(options))
  end

  defp run(scope, project_id, root) do
    with {:ok, scan} <- Store.scan(root) do
      result =
        Enum.reduce(scan.errors, empty_result(), &record_scan_error(&1, &2, scope, project_id))

      result = Enum.reduce(scan.files, result, &sync_file(&1, &2, scope, project_id))
      {:ok, mark_missing(result, scope, project_id, scan.seen)}
    end
  end

  defp sync_file({relative, path}, result, scope, project_id) do
    case Parser.parse_file(path) do
      {:ok, document} -> sync_document(result, relative, document, scope, project_id)
      {:error, reason} -> invalid_file(result, relative, path, scope, project_id, reason)
    end
  end

  defp sync_document(result, relative, document, scope, project_id) do
    with :ok <- expected_scope(document, scope),
         :ok <- expected_kind(document, relative) do
      case indexed_item(scope, project_id, relative) do
        nil -> insert_document(result, relative, document, project_id)
        item -> compare_document(result, item, document)
      end
    else
      {:error, reason} ->
        mark_document_invalid(result, relative, document.hash, scope, project_id, reason)
    end
  end

  defp insert_document(result, relative, document, project_id) do
    attrs =
      Map.merge(document.metadata, %{
        project_id: project_id,
        file_path: relative,
        content_hash: document.hash,
        observed_hash: document.hash,
        sync_state: "synced",
        revision_source: "user"
      })

    case Repo.insert(Item.create_changeset(%Item{}, attrs)) do
      {:ok, item} -> add_result(result, :inserted, item.id)
      {:error, changeset} -> add_error(result, relative, changeset)
    end
  end

  defp compare_document(result, item, %{hash: hash}) when item.content_hash == hash do
    case Repo.update(
           Item.observation_changeset(item, %{observed_hash: hash, sync_state: "synced"})
         ) do
      {:ok, _item} -> add_result(result, :unchanged, item.id)
      {:error, changeset} -> add_error(result, item.file_path, changeset)
    end
  end

  defp compare_document(result, item, document) do
    case Repo.update(
           Item.observation_changeset(item, %{
             observed_hash: document.hash,
             sync_state: "modified"
           })
         ) do
      {:ok, _item} -> add_result(result, :modified, item.id)
      {:error, changeset} -> add_error(result, item.file_path, changeset)
    end
  end

  defp invalid_file(result, relative, path, scope, project_id, reason) do
    case indexed_item(scope, project_id, relative) do
      %Item{} = item -> mark_invalid(result, item, path, reason)
      nil -> add_error(result, relative, reason)
    end
  end

  defp record_scan_error({relative, reason}, result, scope, project_id) do
    if match?({:ok, _kind}, Store.expected_kind(relative)) do
      mark_document_invalid(result, relative, nil, scope, project_id, reason)
    else
      add_error(result, relative, reason)
    end
  end

  defp mark_document_invalid(result, relative, observed_hash, scope, project_id, reason) do
    case indexed_item(scope, project_id, relative) do
      %Item{} = item ->
        case Repo.update(
               Item.observation_changeset(item, %{
                 observed_hash: observed_hash,
                 sync_state: "invalid"
               })
             ) do
          {:ok, _item} ->
            result |> add_result(:invalid, item.id) |> add_error(relative, reason)

          {:error, changeset} ->
            add_error(result, relative, changeset)
        end

      nil ->
        add_error(result, relative, reason)
    end
  end

  defp mark_invalid(result, item, path, reason) do
    observed_hash =
      case Store.file_hash(path) do
        {:ok, hash} -> hash
        _error -> nil
      end

    case Repo.update(
           Item.observation_changeset(item, %{
             observed_hash: observed_hash,
             sync_state: "invalid"
           })
         ) do
      {:ok, _item} -> result |> add_result(:invalid, item.id) |> add_error(item.file_path, reason)
      {:error, changeset} -> add_error(result, item.file_path, changeset)
    end
  end

  defp mark_missing(result, scope, project_id, seen) do
    scope
    |> indexed_items(project_id)
    |> Enum.reject(&MapSet.member?(seen, &1.file_path))
    |> Enum.reduce(result, fn item, current ->
      case Repo.update(
             Item.observation_changeset(item, %{observed_hash: nil, sync_state: "missing"})
           ) do
        {:ok, _item} -> add_result(current, :missing, item.id)
        {:error, changeset} -> add_error(current, item.file_path, changeset)
      end
    end)
  end

  defp expected_scope(%{metadata: %{scope: scope}}, scope), do: :ok
  defp expected_scope(_document, _scope), do: {:error, :knowledge_scope_path_mismatch}

  defp expected_kind(%{metadata: %{kind: kind}}, relative) do
    case Store.expected_kind(relative) do
      {:ok, ^kind} -> :ok
      _other -> {:error, :knowledge_kind_path_mismatch}
    end
  end

  defp indexed_item("project", project_id, relative) do
    Repo.get_by(Item, scope: "project", project_id: project_id, file_path: relative)
  end

  defp indexed_item("global", nil, relative) do
    Repo.get_by(Item, scope: "global", file_path: relative)
  end

  defp indexed_items("project", project_id) do
    Repo.all(
      from(item in Item, where: item.scope == "project" and item.project_id == ^project_id)
    )
  end

  defp indexed_items("global", nil) do
    Repo.all(from(item in Item, where: item.scope == "global"))
  end

  defp empty_result do
    %{
      inserted: [],
      unchanged: [],
      modified: [],
      invalid: [],
      missing: [],
      errors: []
    }
  end

  defp add_result(result, key, id), do: Map.update!(result, key, &[id | &1])

  defp add_error(result, path, reason) do
    Map.update!(result, :errors, &[%{path: path, reason: reason} | &1])
  end
end
