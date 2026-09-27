defmodule Cuckoding.Adapters.ACP.Wire do
  @moduledoc "Bounded ACP v1 JSON-RPC framing and request correlation. Owns no workflow state."

  @maximum_frame 1_048_576
  @maximum_pending 8
  defstruct buffer: "", next_id: 1, pending: %{}

  @doc "Registers a request before its bytes are written to the process."
  def request(%__MODULE__{} = wire, method, params) when is_map(params) do
    with true <- map_size(wire.pending) < @maximum_pending,
         {:ok, frame} <- encode(%{"id" => wire.next_id, "method" => method, "params" => params}) do
      id = wire.next_id
      wire = %{wire | next_id: id + 1, pending: Map.put(wire.pending, id, method)}
      {:ok, wire, id, frame}
    else
      false -> {:error, :acp_pending_limit}
      error -> error
    end
  end

  def notification(method, params) when is_map(params),
    do: encode(%{"method" => method, "params" => params})

  def reply(id, result) when is_map(result), do: encode(%{"id" => id, "result" => result})

  def reject(id),
    do:
      encode(%{
        "id" => id,
        "error" => %{"code" => -32_601, "message" => "Method not supported by this client"}
      })

  @doc "Accepts fragmented/coalesced stdout; returns correlated messages in wire order."
  def feed(%__MODULE__{} = wire, chunk) when is_binary(chunk), do: split(wire, chunk, [])

  def finish(%__MODULE__{buffer: "", pending: pending}) when map_size(pending) == 0, do: :ok
  def finish(%__MODULE__{}), do: {:error, :acp_unexpected_eof}

  defp split(wire, chunk, messages) do
    case :binary.match(chunk, "\n") do
      {offset, 1} ->
        <<part::binary-size(offset), "\n", rest::binary>> = chunk

        with :ok <- size(wire.buffer, part),
             {:ok, decoded} <- decode(wire.buffer <> part),
             {:ok, wire, message} <- correlate(%{wire | buffer: ""}, decoded) do
          split(wire, rest, [message | messages])
        end

      :nomatch ->
        with :ok <- size(wire.buffer, chunk) do
          {:ok, %{wire | buffer: wire.buffer <> chunk}, Enum.reverse(messages)}
        end
    end
  end

  defp size(left, right) when byte_size(left) + byte_size(right) <= @maximum_frame, do: :ok
  defp size(_left, _right), do: {:error, :acp_frame_too_large}

  defp decode(bytes) do
    case Jason.decode(bytes) do
      {:ok, %{"jsonrpc" => "2.0"} = message} -> validate(message)
      _other -> {:error, :acp_invalid_message}
    end
  end

  defp validate(%{"method" => method} = message)
       when is_binary(method) and byte_size(method) in 1..128 do
    params = Map.get(message, "params", %{})

    cond do
      Map.has_key?(message, "result") or Map.has_key?(message, "error") -> invalid()
      not is_map(params) -> invalid()
      not Map.has_key?(message, "id") -> {:ok, {:notification, method, params}}
      valid_id?(message["id"]) -> {:ok, {:request, message["id"], method, params}}
      true -> invalid()
    end
  end

  defp validate(%{"id" => id} = message) do
    cond do
      not valid_id?(id) or Map.has_key?(message, "method") ->
        invalid()

      Map.has_key?(message, "result") and Map.has_key?(message, "error") ->
        invalid()

      is_map(message["result"]) ->
        {:ok, {:response, id, {:ok, message["result"]}}}

      is_map(message["error"]) and is_integer(message["error"]["code"]) ->
        # Provider error text/data may contain credentials or private reasoning.
        {:ok, {:response, id, {:error, message["error"]["code"]}}}

      true ->
        invalid()
    end
  end

  defp validate(_message), do: invalid()
  defp invalid, do: {:error, :acp_invalid_message}
  defp valid_id?(id) when is_integer(id), do: id >= 0
  defp valid_id?(id) when is_binary(id), do: byte_size(id) in 1..128
  defp valid_id?(_id), do: false

  defp correlate(wire, {:response, id, result}) do
    case Map.pop(wire.pending, id) do
      {nil, _pending} -> {:error, :acp_unexpected_response}
      {method, pending} -> {:ok, %{wire | pending: pending}, {:response, id, method, result}}
    end
  end

  defp correlate(wire, message), do: {:ok, wire, message}

  defp encode(message) do
    with {:ok, _message} <- validate(Map.put(message, "jsonrpc", "2.0")),
         {:ok, bytes} <- Jason.encode(Map.put(message, "jsonrpc", "2.0")),
         :ok <- size(bytes, "") do
      {:ok, bytes <> "\n"}
    else
      {:error, %Jason.EncodeError{}} -> invalid()
      error -> error
    end
  end
end
