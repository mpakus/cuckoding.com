defmodule AgentDesk.Providers.Codex.AppServer do
  @moduledoc """
  Codex `app-server` adapter over stdio JSON-RPC.
  """

  @behaviour AgentDesk.Providers.Adapter

  alias AgentDesk.Providers.Capabilities
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Event
  alias AgentDesk.Providers.Fixture
  alias AgentDesk.Providers.JSONRPC
  alias AgentDesk.Providers.Probe

  defstruct jsonrpc: JSONRPC.new()

  @impl true
  def key, do: "codex"

  @impl true
  def display_name, do: "Codex"

  @impl true
  def capabilities do
    %Capabilities{
      key: key(),
      structured_events: true,
      multi_turn: true,
      resume: true,
      steer_active_turn: true,
      approvals: true,
      mcp_stdio: true,
      mcp_http: true,
      file_change_events: true,
      usage_events: true,
      structured_output: true,
      internal_a2a: true,
      safe_boundary_delivery: true
    }
  end

  @impl true
  def probe(opts), do: Probe.probe(key(), "codex", opts)

  @impl true
  def command_spec(session, opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    if Fixture.enabled?(opts ++ [fixture: session.settings["fixture"]]) do
      {:ok, Fixture.command_spec("codex-app-server", Keyword.put(opts, :cwd, cwd))}
    else
      {:ok,
       %CommandSpec{
         executable: Keyword.get(opts, :executable, "codex"),
         args: ["app-server"],
         cwd: cwd
       }}
    end
  end

  @impl true
  def init_decode, do: %__MODULE__{}

  @impl true
  def decode_line(line, %__MODULE__{} = state) do
    case JSONRPC.decode_line(state.jsonrpc, line) do
      {:ok, classified, jsonrpc} ->
        {:ok, events_for(classified), %{state | jsonrpc: jsonrpc}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def encode(:initialize, %__MODULE__{} = state) do
    request(state, "initialize", %{"clientInfo" => %{"name" => "AgentDesk", "version" => "0.1.0"}})
  end

  def encode(:initialized, state) do
    {:ok, JSONRPC.notification("initialized", %{}), state}
  end

  def encode({:start_session, cwd}, state) do
    request(state, "thread/start", %{"cwd" => cwd})
  end

  def encode({:resume, thread_id}, state) do
    request(state, "thread/resume", %{"threadId" => thread_id})
  end

  def encode({:prompt, text}, state) do
    request(state, "turn/start", %{"input" => [%{"type" => "text", "text" => text}]})
  end

  def encode(:interrupt, state), do: request(state, "turn/interrupt", %{})

  def encode({:approve, request_id, decision}, state) do
    id = parse_id(request_id)
    {:ok, JSONRPC.response(id, %{"decision" => decision}), state}
  end

  def encode({:configure_mcp, path}, state) do
    request(state, "session/configure_mcp", %{"path" => path})
  end

  def encode(_action, _state), do: {:error, :unsupported_action}

  defp events_for({:response, _id, result, "initialize"}) when is_map(result) do
    [Event.new(:initialize_result, stringify(result), "codex")]
  end

  defp events_for({:response, _id, %{"threadId" => thread_id}, _method})
       when is_binary(thread_id) do
    [Event.new(:session_ready, %{"provider_session_id" => thread_id}, "codex")]
  end

  defp events_for({:response, _id, result, "turn/start"}) do
    [Event.new(:turn_started, stringify(result), "codex")]
  end

  defp events_for({:response, _id, _result, _method}), do: []

  defp events_for({:error_response, _id, error, _method}) do
    [Event.new(:provider_error, stringify(error), "codex")]
  end

  defp events_for({:notification, "item/agentMessage/delta", params}) do
    [Event.new(:message_delta, %{"text" => params["delta"] || ""}, "codex")]
  end

  defp events_for({:notification, "item/fileChange", params}) do
    [Event.new(:file_change, stringify(params), "codex")]
  end

  defp events_for({:notification, "turn/completed", params}) do
    [Event.new(:turn_completed, stringify(params), "codex")]
  end

  defp events_for({:request, id, "approval/request", params}) do
    [
      Event.new(
        :approval_requested,
        %{
          "request_id" => to_string(id),
          "action" => params["action"],
          "summary" => params["summary"]
        },
        "codex"
      )
    ]
  end

  defp events_for({:notification, _method, _params}), do: []
  defp events_for({:request, _id, _method, _params}), do: []

  defp request(%__MODULE__{} = state, method, params) do
    {encoded, jsonrpc} = JSONRPC.request(state.jsonrpc, method, params)
    {:ok, encoded, %{state | jsonrpc: jsonrpc}}
  end

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp parse_id(id) do
    case Integer.parse(to_string(id)) do
      {int, ""} -> int
      _ -> id
    end
  end
end
