defmodule AgentDesk.Providers.ACP.Client do
  @moduledoc """
  Shared ACP JSON-RPC client: framing is owned by the session worker; this
  module owns request IDs, initialize/session methods, and unknown-method replies.
  """

  alias AgentDesk.Providers.ACP.Protocol
  alias AgentDesk.Providers.Event
  alias AgentDesk.Providers.JSONRPC

  defstruct jsonrpc: JSONRPC.new(),
            provider: "acp",
            protocol_version: nil,
            session_id: nil

  @type t :: %__MODULE__{
          jsonrpc: JSONRPC.t(),
          provider: String.t(),
          protocol_version: String.t() | nil,
          session_id: String.t() | nil
        }

  @spec new(String.t()) :: t()
  def new(provider) when is_binary(provider), do: %__MODULE__{provider: provider}

  @spec encode(t(), AgentDesk.Providers.Adapter.action()) ::
          {:ok, iodata(), t()} | {:error, term()}
  def encode(%__MODULE__{} = client, :initialize) do
    request(client, "initialize", %{
      "protocolVersion" => 1,
      "clientInfo" => %{"name" => "AgentDesk", "version" => "0.1.0"},
      "capabilities" => %{"fs" => %{"readTextFile" => true, "writeTextFile" => false}}
    })
  end

  def encode(%__MODULE__{} = client, :initialized) do
    {:ok, JSONRPC.notification("initialized", %{}), client}
  end

  def encode(%__MODULE__{} = client, {:start_session, cwd}) do
    request(client, "session/new", %{"cwd" => cwd, "mcpServers" => []})
  end

  def encode(%__MODULE__{} = client, {:resume, session_id}) do
    request(client, "session/load", %{"sessionId" => session_id})
  end

  def encode(%__MODULE__{} = client, {:prompt, text}) do
    request(client, "session/prompt", %{
      "sessionId" => client.session_id,
      "prompt" => [%{"type" => "text", "text" => text}]
    })
  end

  def encode(%__MODULE__{} = client, :interrupt) do
    request(client, "session/cancel", %{"sessionId" => client.session_id})
  end

  def encode(%__MODULE__{} = client, {:approve, request_id, decision}) do
    id = parse_id(request_id)
    result = %{"outcome" => %{"outcome" => decision_outcome(decision)}}
    {:ok, JSONRPC.response(id, result), client}
  end

  def encode(%__MODULE__{} = client, {:configure_mcp, path}) do
    request(client, "session/configure_mcp", %{"path" => path, "sessionId" => client.session_id})
  end

  def encode(%__MODULE__{} = client, {:reject_method, id, method}) do
    {:ok, JSONRPC.error_response(id, -32_601, "Unsupported method #{method}"), client}
  end

  def encode(_client, _action), do: {:error, :unsupported_action}

  @spec decode_line(t(), String.t()) :: {:ok, [Event.t()], t()} | {:error, term()}
  def decode_line(%__MODULE__{} = client, line) do
    case JSONRPC.decode_line(client.jsonrpc, line) do
      {:ok, classified, jsonrpc} ->
        client = %{client | jsonrpc: jsonrpc}
        handle(client, classified)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle(client, {:response, _id, result, "initialize"}) when is_map(result) do
    version = protocol_version(result)

    {:ok, [Event.new(:initialize_result, stringify(result), client.provider)],
     %{client | protocol_version: version}}
  end

  defp handle(client, {:response, _id, result, "session/prompt"}) do
    {:ok, [Event.new(:turn_completed, stringify(result), client.provider)], client}
  end

  defp handle(client, {:response, _id, result, _method}) when is_map(result) do
    case session_id(result) do
      id when is_binary(id) ->
        event = Event.new(:session_ready, %{"provider_session_id" => id}, client.provider)
        {:ok, [event], %{client | session_id: id}}

      _ ->
        {:ok, [], client}
    end
  end

  defp handle(client, {:error_response, _id, error, _method}) do
    {:ok, [Event.new(:provider_error, stringify(error), client.provider)], client}
  end

  defp handle(client, {:notification, "session/update", params}) do
    {:ok, Protocol.from_update(params, client.provider), client}
  end

  defp handle(client, {:notification, "session/exited", params}) do
    {:ok, [Event.new(:session_exited, stringify(params), client.provider)], client}
  end

  defp handle(client, {:request, id, "session/request_permission", params}) do
    {:ok, [Protocol.from_permission(id, params, client.provider)], client}
  end

  defp handle(client, {:request, id, method, params}) do
    event =
      Event.new(
        :provider_error,
        %{
          "unsupported_method" => method,
          "request_id" => to_string(id),
          "params" => params
        },
        client.provider
      )

    {:ok, [event], client}
  end

  defp handle(client, {:notification, _method, _params}) do
    {:ok, [], client}
  end

  defp request(client, method, params) do
    {encoded, jsonrpc} = JSONRPC.request(client.jsonrpc, method, params)
    {:ok, encoded, %{client | jsonrpc: jsonrpc}}
  end

  defp session_id(result) when is_map(result) do
    result["sessionId"] || result["session_id"]
  end

  defp protocol_version(result) when is_map(result) do
    case result["protocolVersion"] || get_in(result, ["protocol", "version"]) do
      version when is_binary(version) -> version
      version when is_integer(version) -> Integer.to_string(version)
      _ -> nil
    end
  end

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp parse_id(id) do
    case Integer.parse(to_string(id)) do
      {int, ""} -> int
      _ -> id
    end
  end

  defp decision_outcome("allow"), do: "selected"
  defp decision_outcome("approve"), do: "selected"
  defp decision_outcome(_deny), do: "cancelled"
end
