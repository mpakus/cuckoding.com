defmodule CuckodingWeb.KnowledgeRetrievalController do
  use CuckodingWeb, :controller

  alias Cuckoding.Knowledge

  def create(conn, %{"query" => query} = params) do
    with {:ok, token} <- bearer(conn),
         {:ok, result} <- Knowledge.retrieve(token, query, limit: params["limit"] || 5) do
      json(conn, result)
    else
      {:error, reason}
      when reason in [:knowledge_capability_invalid, :knowledge_capability_expired] ->
        conn |> put_status(:unauthorized) |> json(%{error: Atom.to_string(reason)})

      {:error, :authorization_required} ->
        conn |> put_status(:unauthorized) |> json(%{error: "authorization_required"})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: error_name(reason)})
    end
  end

  def create(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "query_required"})
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _headers -> {:error, :authorization_required}
    end
  end

  defp error_name(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_name(_reason), do: "knowledge_retrieval_failed"
end
