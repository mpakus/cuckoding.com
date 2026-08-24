defmodule AgentDesk.Providers.Codex.AppServer do
  @moduledoc """
  Codex `app-server` adapter over stdio JSON-RPC.

  The current protocol omits the JSON-RPC version header and returns threads as
  `{thread: %{id: ...}}` rather than a top-level `threadId`.
  """

  @behaviour AgentDesk.Providers.Adapter

  alias AgentDesk.Branding
  alias AgentDesk.Providers.Capabilities
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Event
  alias AgentDesk.Providers.Fixture
  alias AgentDesk.Providers.JSONRPC
  alias AgentDesk.Providers.Probe
  alias AgentDesk.Providers.Prompt

  defstruct jsonrpc: JSONRPC.new(header: false), thread_id: nil, turn_id: nil

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
        {events, state} = consume(classified, %{state | jsonrpc: jsonrpc})
        {:ok, events, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def encode(:initialize, %__MODULE__{} = state) do
    request(state, "initialize", %{
      "clientInfo" => %{
        "name" => "cuckoding",
        "title" => Branding.product_name(),
        "version" => "0.1.0"
      }
    })
  end

  def encode(:initialized, %__MODULE__{} = state) do
    {:ok, JSONRPC.notification(state.jsonrpc, "initialized", %{}), state}
  end

  def encode({:start_session, cwd}, state) do
    request(state, "thread/start", %{"cwd" => cwd})
  end

  def encode({:resume, thread_id}, state) do
    request(%{state | thread_id: thread_id}, "thread/resume", %{"threadId" => thread_id})
  end

  def encode({:prompt, text}, state), do: encode({:prompt, text, []}, state)

  def encode({:prompt, text, attachments}, %__MODULE__{thread_id: thread_id} = state)
      when is_binary(thread_id) do
    request(state, "turn/start", %{
      "threadId" => thread_id,
      "input" => prompt_input(text, attachments)
    })
  end

  def encode({:prompt, text, attachments}, state) do
    request(state, "turn/start", %{"input" => prompt_input(text, attachments)})
  end

  def encode(:interrupt, %__MODULE__{} = state) do
    params =
      %{}
      |> maybe_put("threadId", state.thread_id)
      |> maybe_put("turnId", state.turn_id)

    request(state, "turn/interrupt", params)
  end

  def encode({:approve, request_id, decision}, state) do
    {:ok, JSONRPC.response(state.jsonrpc, parse_id(request_id), %{"decision" => decision}), state}
  end

  def encode({:configure_mcp, _path}, state), do: {:ok, "", state}

  def encode(_action, _state), do: {:error, :unsupported_action}

  defp consume({:response, _id, result, "initialize"}, state) when is_map(result) do
    {[Event.new(:initialize_result, stringify(result), "codex")], state}
  end

  defp consume({:response, _id, result, method}, state)
       when method in ["thread/start", "thread/resume", "thread/fork"] do
    remember_thread(state, thread_id(result), :session_ready)
  end

  defp consume({:response, _id, result, "turn/start"}, state) do
    turn_id = get_in(result, ["turn", "id"]) || result["turnId"]
    state = if is_binary(turn_id), do: %{state | turn_id: turn_id}, else: state
    {[Event.new(:turn_started, stringify(result), "codex")], state}
  end

  defp consume({:response, _id, result, _method}, state) do
    remember_thread(state, thread_id(result), :session_ready)
  end

  defp consume({:error_response, _id, error, _method}, state) do
    {[Event.new(:provider_error, stringify(error), "codex")], state}
  end

  defp consume({:notification, "thread/started", params}, state) do
    remember_thread(state, thread_id(params), :session_ready)
  end

  defp consume({:notification, "item/agentMessage/delta", params}, state) do
    {[Event.new(:message_delta, %{"text" => params["delta"] || params["text"] || ""}, "codex")],
     state}
  end

  defp consume({:notification, "item/fileChange", params}, state) do
    {[Event.new(:file_change, stringify(params), "codex")], state}
  end

  defp consume({:notification, "turn/completed", params}, state) do
    {[Event.new(:turn_completed, stringify(params), "codex")], %{state | turn_id: nil}}
  end

  defp consume({:request, id, "approval/request", params}, state) do
    {[
       Event.new(
         :approval_requested,
         %{
           "request_id" => to_string(id),
           "action" => params["action"],
           "summary" => params["summary"]
         },
         "codex"
       )
     ], state}
  end

  defp consume({:notification, _method, _params}, state), do: {[], state}
  defp consume({:request, _id, _method, _params}, state), do: {[], state}

  defp remember_thread(%__MODULE__{thread_id: id} = state, id, _kind) when is_binary(id) do
    {[], state}
  end

  defp remember_thread(state, id, :session_ready) when is_binary(id) do
    {[Event.new(:session_ready, %{"provider_session_id" => id}, "codex")],
     %{state | thread_id: id}}
  end

  defp remember_thread(state, _id, _kind), do: {[], state}

  defp thread_id(%{"threadId" => id}) when is_binary(id) and id != "", do: id
  defp thread_id(%{"thread" => %{"id" => id}}) when is_binary(id) and id != "", do: id
  defp thread_id(_), do: nil

  defp request(%__MODULE__{} = state, method, params) do
    {encoded, jsonrpc} = JSONRPC.request(state.jsonrpc, method, params)
    {:ok, encoded, %{state | jsonrpc: jsonrpc}}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value) when is_binary(value), do: Map.put(map, key, value)

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp parse_id(id) do
    case Integer.parse(to_string(id)) do
      {int, ""} -> int
      _ -> id
    end
  end

  defp prompt_input(text, attachments) do
    text_item = %{"type" => "text", "text" => Prompt.with_file_notes(text, attachments)}

    image_items =
      Enum.map(Prompt.images(attachments), fn att ->
        case Prompt.inline_image(att) do
          {:ok, mime, data} ->
            %{"type" => "image", "url" => "data:#{mime};base64,#{data}"}

          :error ->
            %{"type" => "localImage", "path" => att["path"]}
        end
      end)

    [text_item | image_items]
  end
end
