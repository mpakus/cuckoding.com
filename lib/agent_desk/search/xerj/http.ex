defmodule AgentDesk.Search.Xerj.HTTP do
  @moduledoc false

  @spec get(String.t()) :: {:ok, map() | String.t()} | {:error, term()}
  def get(url), do: request(:get, url, nil)

  @spec post(String.t(), map()) :: {:ok, map() | String.t()} | {:error, term()}
  def post(url, body), do: request(:post, url, body)

  @spec delete(String.t()) :: {:ok, map() | String.t()} | {:error, term()}
  def delete(url), do: request(:delete, url, nil)

  defp request(method, url, body) do
    payload = if body, do: Jason.encode!(body), else: ""
    headers = [{~c"content-type", ~c"application/json"}]
    request = {String.to_charlist(url), headers, ~c"application/json", payload}

    http_request =
      case method do
        :get -> :httpc.request(:get, {String.to_charlist(url), []}, [{:timeout, 3_000}], [])
        :delete -> :httpc.request(:delete, {String.to_charlist(url), []}, [{:timeout, 3_000}], [])
        :post -> :httpc.request(:post, request, [{:timeout, 8_000}], [])
      end

    decode(http_request)
  rescue
    error -> {:error, error}
  end

  defp decode({:ok, {{_v, status, _}, _headers, body}}) when status in 200..299 do
    text = IO.iodata_to_binary(body)

    case Jason.decode(text) do
      {:ok, map} -> {:ok, map}
      {:error, _} -> {:ok, text}
    end
  end

  defp decode({:ok, {{_v, status, _}, _headers, body}}) do
    {:error, {status, IO.iodata_to_binary(body)}}
  end

  defp decode({:error, reason}), do: {:error, reason}
end
