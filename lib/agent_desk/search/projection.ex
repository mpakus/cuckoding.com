defmodule AgentDesk.Search.Projection do
  @moduledoc """
  Rebuildable SQLite search/memory projection used when XERJ is off or missing.
  """

  @behaviour AgentDesk.Search.Adapter

  import Ecto.Query

  alias AgentDesk.Ids
  alias AgentDesk.Repo
  alias AgentDesk.Search.Document
  alias AgentDesk.Search.Memory

  @max_results 8
  @max_bytes 8_000

  @impl true
  def health(_ctx), do: :ok

  @impl true
  def index_project(_project), do: :ok

  @impl true
  def index_documents(%{id: project_id}, docs) when is_list(docs) do
    Enum.each(docs, &upsert_doc(project_id, &1))
    :ok
  end

  @impl true
  def search(%{id: project_id}, query) when is_map(query) do
    q = String.downcase(to_string(query[:q] || query["q"] || ""))

    Document
    |> where([d], d.project_id == ^project_id)
    |> Repo.all()
    |> Enum.filter(&String.contains?(String.downcase(&1.passage <> &1.title), q))
    |> Enum.sort_by(&source_rank/1)
    |> Enum.take(@max_results)
    |> bound()
    |> then(&{:ok, &1})
  end

  @impl true
  def remember(namespace, memory) do
    %Memory{}
    |> Memory.changeset(%{
      id: memory[:id] || Ids.generate(),
      project_id: memory[:project_id],
      namespace: namespace,
      text: memory[:text] || memory["text"],
      metadata: memory[:metadata] || memory["metadata"] || %{}
    })
    |> Repo.insert()
    |> case do
      {:ok, row} -> {:ok, public_memory(row)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def recall(namespace, query) do
    q =
      String.downcase(to_string(query[:q] || query["q"] || query[:query] || query["query"] || ""))

    Memory
    |> where([m], m.namespace == ^namespace)
    |> order_by([m], desc: m.inserted_at)
    |> limit(20)
    |> Repo.all()
    |> Enum.filter(&String.contains?(String.downcase(&1.text), q))
    |> Enum.map(&public_memory/1)
    |> then(&{:ok, &1})
  end

  @impl true
  def forget(namespace, id) do
    Memory
    |> where([m], m.id == ^id and m.namespace == ^namespace)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def rebuild(project), do: purge(project)

  @impl true
  def purge(%{id: project_id}) do
    Document |> where([d], d.project_id == ^project_id) |> Repo.delete_all()
    Memory |> where([m], m.project_id == ^project_id) |> Repo.delete_all()
    :ok
  end

  defp upsert_doc(project_id, doc) do
    source = doc[:source] || doc["source"]
    source_id = doc[:source_id] || doc["source_id"]
    hash = doc[:content_hash] || doc["content_hash"]

    attrs = %{
      id: Ids.generate(),
      project_id: project_id,
      source: source,
      source_id: source_id,
      title: doc[:title] || doc["title"] || source_id,
      passage: String.slice(doc[:passage] || doc["passage"] || "", 0, 4_000),
      path: doc[:path] || doc["path"],
      content_hash: hash
    }

    %Document{}
    |> Document.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:title, :passage, :path, :content_hash]},
      conflict_target: [:project_id, :source, :source_id]
    )
  end

  defp source_rank(%{source: "project_file"}), do: 0
  defp source_rank(%{source: "handoff"}), do: 1
  defp source_rank(%{source: "artifact"}), do: 2
  defp source_rank(_), do: 3

  defp bound(docs) do
    Enum.reduce_while(docs, {[], 0}, fn doc, {acc, bytes} ->
      passage = String.slice(doc.passage, 0, 1_200)
      size = byte_size(passage)

      if bytes + size > @max_bytes do
        {:halt, {acc, bytes}}
      else
        {:cont, {acc ++ [public_doc(doc, passage)], bytes + size}}
      end
    end)
    |> elem(0)
  end

  defp public_doc(doc, passage) do
    %{
      source: doc.source,
      source_id: doc.source_id,
      title: doc.title,
      passage: passage,
      score: 1.0,
      retrieval: "lexical",
      metadata: %{"path" => doc.path, "content_hash" => doc.content_hash}
    }
  end

  defp public_memory(row) do
    %{id: row.id, namespace: row.namespace, text: row.text, metadata: row.metadata}
  end
end
