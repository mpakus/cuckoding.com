defmodule AgentDesk.Search.Xerj do
  @moduledoc """
  XERJ HTTP adapter. LiveView and providers never call this module directly.
  """

  @behaviour AgentDesk.Search.Adapter

  alias AgentDesk.Search.Xerj.HTTP
  alias AgentDesk.Search.Xerj.Process

  @impl true
  def health(_ctx) do
    if Process.owned?() do
      case HTTP.get(Process.base_url() <> "/") do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :unavailable}
    end
  end

  @impl true
  def index_project(%{canonical_path: path}) do
    exe = AgentDesk.Search.Xerj.Discovery.executable()

    cond do
      not Process.owned?() ->
        {:error, :unavailable}

      is_nil(exe) ->
        {:error, :unavailable}

      true ->
        {_out, status} =
          System.cmd(exe, ["autoindex", path, "--url", Process.base_url(), "--no-graph"],
            stderr_to_stdout: true
          )

        if status in [0, 3], do: :ok, else: {:error, :index_failed}
    end
  end

  @impl true
  def index_documents(_project, _docs), do: :ok

  @impl true
  def search(_project, query) do
    with :ok <- require_owned() do
      body = %{
        "query" => %{"query_string" => %{"query" => query[:q] || query["q"] || "*"}},
        "size" => 8
      }

      case HTTP.post(Process.base_url() <> "/_search", body) do
        {:ok, result} -> {:ok, hits(result)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def remember(namespace, memory) do
    with :ok <- require_owned() do
      body = %{
        "text" => memory[:text] || memory["text"],
        "metadata" => memory[:metadata] || memory["metadata"] || %{},
        "id" => memory[:id]
      }

      HTTP.post(Process.base_url() <> "/_memory/" <> namespace, body)
    end
  end

  @impl true
  def recall(namespace, query) do
    with :ok <- require_owned() do
      body = %{"query" => query[:q] || query["q"] || query[:query] || query["query"], "k" => 5}

      case HTTP.post(Process.base_url() <> "/_memory/" <> namespace <> "/_recall", body) do
        {:ok, result} -> {:ok, hits(result)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def forget(namespace, id) do
    with :ok <- require_owned() do
      case HTTP.delete(Process.base_url() <> "/_memory/" <> namespace <> "/" <> id) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def rebuild(project), do: index_project(project)

  @impl true
  def purge(_project), do: :ok

  defp hits(%{"hits" => %{"hits" => list}}) when is_list(list) do
    Enum.map(list, &hit/1)
  end

  defp hits(%{"hits" => list}) when is_list(list), do: Enum.map(list, &hit/1)
  defp hits(_), do: []

  defp require_owned do
    if Process.owned?(), do: :ok, else: {:error, :unavailable}
  end

  defp hit(hit) do
    source = hit["_source"] || hit
    path = source["path"] || source["file"] || hit["_id"]

    %{
      source: "project_file",
      source_id: path,
      title: source["title"] || path,
      passage:
        String.slice(source["content"] || source["text"] || source["body"] || "", 0, 1_200),
      score: hit["_score"] || 0,
      retrieval: "lexical",
      metadata: %{"path" => path}
    }
  end
end
