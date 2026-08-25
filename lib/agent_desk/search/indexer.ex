defmodule AgentDesk.Search.Indexer do
  @moduledoc """
  Rebuilds search documents from the project filesystem and canonical SQLite.
  """

  alias AgentDesk.A2A
  alias AgentDesk.Clock
  alias AgentDesk.Events
  alias AgentDesk.Ids
  alias AgentDesk.Projects.Project
  alias AgentDesk.Repo
  alias AgentDesk.Scope
  alias AgentDesk.Search
  alias AgentDesk.Search.Exclusions
  alias AgentDesk.Search.IndexState

  @spec index_project(Project.t()) :: :ok | {:error, term()}
  def index_project(%Project{} = project) do
    case mark(project, "indexing", nil) do
      :ok -> do_index_project(project)
      {:error, reason} -> {:error, {:index_status_unavailable, reason}}
    end
  end

  defp do_index_project(%Project{} = project) do
    docs =
      file_docs(project) ++
        artifact_docs(project) ++
        event_docs(project) ++
        handoff_docs(project)

    result = Search.adapter().index_documents(%{id: project.id}, docs)
    maybe_xerj(project)

    case result do
      :ok ->
        finish(project, "ready", nil, :ok)

      {:error, :unavailable} ->
        finish(project, "unavailable", nil, {:error, :unavailable})

      {:error, reason} ->
        finish(project, "error", human_reason(reason), {:error, reason})
    end
  rescue
    error ->
      _ = mark(project, "error", Exception.message(error))
      {:error, error}
  catch
    kind, reason ->
      _ = mark(project, "error", human_reason(reason))
      {:error, {kind, reason}}
  end

  @spec rebuild(Project.t()) :: :ok | {:error, term()}
  def rebuild(%Project{} = project) do
    _ = Search.adapter().purge(%{id: project.id})
    index_project(project)
  end

  @spec status(Ecto.UUID.t()) :: IndexState.t() | nil
  def status(project_id) do
    Repo.get_by(IndexState, project_id: project_id)
  end

  defp maybe_xerj(project) do
    if Search.adapter() == AgentDesk.Search.Xerj do
      Search.adapter().index_project(%{canonical_path: project.canonical_path})
    else
      :ok
    end
  end

  defp file_docs(%Project{} = project) do
    project.canonical_path
    |> walk([])
    |> Enum.map(fn path ->
      rel = Path.relative_to(path, project.canonical_path)

      body =
        case File.read(path) do
          {:ok, contents} -> String.slice(contents, 0, 4_000)
          {:error, _} -> ""
        end

      hash = :sha256 |> :crypto.hash(body) |> Base.encode16(case: :lower)

      %{
        source: "project_file",
        source_id: rel,
        title: rel,
        passage: body,
        path: rel,
        content_hash: hash
      }
    end)
  end

  defp walk(dir, acc) do
    case File.ls(dir) do
      {:ok, names} -> Enum.reduce(names, acc, &walk_entry(dir, &1, &2))
      {:error, _} -> acc
    end
  end

  defp walk_entry(dir, name, acc) do
    path = Path.join(dir, name)

    cond do
      Exclusions.skip_dir?(name) or Exclusions.skip_file?(name) ->
        acc

      File.dir?(path) ->
        walk(path, acc)

      Exclusions.text_file?(path) ->
        [path | acc]

      true ->
        acc
    end
  end

  defp artifact_docs(%Project{} = project) do
    project
    |> Scope.for_project()
    |> A2A.list_artifacts()
    |> Enum.map(fn artifact ->
      %{
        source: "artifact",
        source_id: artifact.id,
        title: artifact.name,
        passage: artifact.name <> " " <> artifact.kind,
        path: artifact.path,
        content_hash: artifact.sha256
      }
    end)
  end

  defp event_docs(%Project{} = project) do
    project.id
    |> Events.list_for_project(limit: 50)
    |> Enum.reject(&(&1.type in ["project.opened", "project.closed"]))
    |> Enum.map(fn event ->
      passage = event.type <> " " <> Jason.encode!(event.payload || %{})
      hash = :sha256 |> :crypto.hash(passage) |> Base.encode16(case: :lower)

      %{
        source: "event",
        source_id: event.id,
        title: event.type,
        passage: String.slice(passage, 0, 1_000),
        path: nil,
        content_hash: hash
      }
    end)
  end

  defp handoff_docs(%Project{} = project) do
    project
    |> Scope.for_project()
    |> A2A.list_artifacts()
    |> Enum.filter(&(&1.kind == "handoff"))
    |> Enum.map(fn artifact ->
      %{
        source: "handoff",
        source_id: artifact.id,
        title: artifact.name,
        passage: inspect(artifact.metadata),
        path: artifact.path,
        content_hash: artifact.sha256
      }
    end)
  end

  defp mark(%Project{} = project, status, error) do
    attrs = %{
      id: Ids.generate(),
      project_id: project.id,
      status: status,
      adapter: adapter_name(),
      last_indexed_at: Clock.utc_now(),
      error: error
    }

    %IndexState{}
    |> IndexState.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:status, :adapter, :last_indexed_at, :error, :updated_at]},
      conflict_target: [:project_id]
    )
    |> case do
      {:ok, _state} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp finish(project, status, error, result) do
    case mark(project, status, error) do
      :ok -> result
      {:error, reason} -> {:error, {:index_status_unavailable, reason}}
    end
  end

  defp adapter_name do
    Search.adapter() |> Module.split() |> List.last()
  end

  defp human_reason(:unavailable), do: nil

  defp human_reason(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp human_reason(reason) when is_binary(reason), do: reason

  defp human_reason(reason) do
    if is_exception(reason), do: Exception.message(reason), else: inspect(reason)
  end
end
