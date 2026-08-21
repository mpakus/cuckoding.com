defmodule AgentDesk.Providers.JSONRPC do
  @moduledoc """
  JSON-RPC 2.0 request correlation for stdio transports.

  Request IDs are integers generated here, never atoms derived from payloads.
  """

  defstruct next_id: 1, pending: %{}

  @type t :: %__MODULE__{next_id: pos_integer(), pending: map()}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec request(t(), String.t(), map()) :: {String.t(), t()}
  def request(%__MODULE__{} = state, method, params) when is_binary(method) and is_map(params) do
    id = state.next_id

    encoded =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => method,
        "params" => params
      })

    pending = Map.put(state.pending, id, method)
    {encoded <> "\n", %{state | next_id: id + 1, pending: pending}}
  end

  @spec notification(String.t(), map()) :: String.t()
  def notification(method, params) when is_binary(method) and is_map(params) do
    Jason.encode!(%{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params
    }) <> "\n"
  end

  @spec response(term(), map()) :: String.t()
  def response(id, result) when is_map(result) do
    Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result}) <> "\n"
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
      {:ok, %{"jsonrpc" => "2.0"} = msg} -> classify(state, msg)
      {:ok, _} -> {:error, :not_jsonrpc}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp classify(state, %{"id" => id, "result" => result}) do
    {method, pending} = Map.pop(state.pending, id)
    {:ok, {:response, id, result, method}, %{state | pending: pending}}
  end

  defp classify(state, %{"id" => id, "error" => error}) do
    {method, pending} = Map.pop(state.pending, id)
    {:ok, {:error_response, id, error, method}, %{state | pending: pending}}
  end

  defp classify(state, %{"id" => id, "method" => method} = msg) when is_binary(method) do
    {:ok, {:request, id, method, Map.get(msg, "params", %{})}, state}
  end

  defp classify(state, %{"method" => method} = msg) when is_binary(method) do
    {:ok, {:notification, method, Map.get(msg, "params", %{})}, state}
  end

  defp classify(_state, _msg), do: {:error, :unrecognized_jsonrpc}
end
