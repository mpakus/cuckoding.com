defmodule AgentDesk.Providers.JSONRPC do
  @moduledoc """
  JSON-RPC 2.0 request correlation for stdio transports.

  Request IDs are integers generated here, never atoms derived from payloads.
  Codex app-server omits the `"jsonrpc":"2.0"` header on the wire; ACP keeps it.
  """

  defstruct next_id: 1, pending: %{}, header: true

  @type t :: %__MODULE__{next_id: pos_integer(), pending: map(), header: boolean()}

  @spec new() :: t()
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{header: Keyword.get(opts, :header, true)}
  end

  @spec request(t(), String.t(), map()) :: {String.t(), t()}
  def request(%__MODULE__{} = state, method, params) when is_binary(method) and is_map(params) do
    id = state.next_id
    encoded = envelope(state, %{"id" => id, "method" => method, "params" => params})
    pending = Map.put(state.pending, id, method)
    {encoded, %{state | next_id: id + 1, pending: pending}}
  end

  @spec notification(String.t(), map()) :: String.t()
  def notification(method, params) when is_binary(method) and is_map(params) do
    notification(%__MODULE__{header: true}, method, params)
  end

  @spec notification(t(), String.t(), map()) :: String.t()
  def notification(%__MODULE__{} = state, method, params)
      when is_binary(method) and is_map(params) do
    envelope(state, %{"method" => method, "params" => params})
  end

  @spec response(term(), map()) :: String.t()
  def response(id, result) when is_map(result) do
    response(%__MODULE__{header: true}, id, result)
  end

  @spec response(t(), term(), map()) :: String.t()
  def response(%__MODULE__{} = state, id, result) when is_map(result) do
    envelope(state, %{"id" => id, "result" => result})
  end

  @spec error_response(term(), integer(), String.t()) :: String.t()
  def error_response(id, code, message) do
    Jason.encode!(%{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message}
    }) <> "\n"
  end

  @spec decode_line(t(), String.t()) ::
          {:ok, {:response, term(), map(), String.t() | nil}, t()}
          | {:ok, {:error_response, term(), map(), String.t() | nil}, t()}
          | {:ok, {:notification, String.t(), map()}, t()}
          | {:ok, {:request, term(), String.t(), map()}, t()}
          | {:error, term()}
  def decode_line(%__MODULE__{} = state, line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, msg} when is_map(msg) -> classify(state, msg)
      {:ok, _} -> {:error, :not_jsonrpc}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp envelope(%__MODULE__{header: true}, map) do
    Jason.encode!(Map.put(map, "jsonrpc", "2.0")) <> "\n"
  end

  defp envelope(%__MODULE__{header: false}, map) do
    Jason.encode!(map) <> "\n"
  end

  defp classify(state, %{"id" => id, "result" => result}) do
    {method, pending} = pop_pending(state.pending, id)
    {:ok, {:response, id, result, method}, %{state | pending: pending}}
  end

  defp classify(state, %{"id" => id, "error" => error}) do
    {method, pending} = pop_pending(state.pending, id)
    {:ok, {:error_response, id, error, method}, %{state | pending: pending}}
  end

  defp classify(state, %{"id" => id, "method" => method} = msg) when is_binary(method) do
    {:ok, {:request, id, method, Map.get(msg, "params", %{})}, state}
  end

  defp classify(state, %{"method" => method} = msg) when is_binary(method) do
    {:ok, {:notification, method, Map.get(msg, "params", %{})}, state}
  end

  defp classify(_state, _msg), do: {:error, :unrecognized_jsonrpc}

  defp pop_pending(pending, id) do
    cond do
      Map.has_key?(pending, id) ->
        Map.pop(pending, id)

      is_binary(id) ->
        case Integer.parse(id) do
          {int, ""} -> Map.pop(pending, int, nil)
          _ -> {nil, pending}
        end

      is_integer(id) ->
        Map.pop(pending, Integer.to_string(id), nil)

      true ->
        {nil, pending}
    end
  end
end
