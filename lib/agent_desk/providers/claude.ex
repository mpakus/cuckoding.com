defmodule AgentDesk.Providers.Claude do
  @moduledoc """
  Claude Code structured stream-json adapter.
  """

  @behaviour AgentDesk.Providers.Adapter

  alias AgentDesk.Providers.Capabilities
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Event
  alias AgentDesk.Providers.Fixture
  alias AgentDesk.Providers.Probe

  defstruct []

  @impl true
  def key, do: "claude"

  @impl true
  def display_name, do: "Claude Code"

  @impl true
  def capabilities do
    %Capabilities{
      key: key(),
      structured_events: true,
      multi_turn: true,
      resume: true,
      steer_active_turn: false,
      approvals: false,
      mcp_stdio: true,
      file_change_events: false,
      usage_events: true,
      structured_output: true,
      internal_a2a: true,
      safe_boundary_delivery: true
    }
  end

  @impl true
  def probe(opts), do: Probe.probe(key(), "claude", opts)

  @impl true
  def command_spec(session, opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    if Fixture.enabled?(opts ++ [fixture: session.settings["fixture"]]) do
      {:ok, Fixture.command_spec("claude", Keyword.put(opts, :cwd, cwd))}
    else
      {:ok,
       %CommandSpec{
         executable: Keyword.get(opts, :executable, "claude"),
         args: [
           "-p",
           "--output-format",
           "stream-json",
           "--verbose",
           "--input-format",
           "stream-json"
         ],
         cwd: cwd
       }}
    end
  end

  @impl true
  def init_decode, do: %__MODULE__{}

  @impl true
  def decode_line(line, %__MODULE__{} = state) do
    case Jason.decode(line) do
      {:ok, %{"type" => "system", "subtype" => "init"} = msg} ->
        {:ok,
         [Event.new(:session_ready, %{"provider_session_id" => msg["session_id"]}, "claude")],
         state}

      {:ok, %{"type" => "assistant"} = msg} ->
        text = get_in(msg, ["message", "content"]) |> text_content()
        {:ok, [Event.new(:message_delta, %{"text" => text}, "claude")], state}

      {:ok, %{"type" => "result"} = msg} ->
        type = if msg["subtype"] == "interrupted", do: :session_exited, else: :turn_completed
        {:ok, [Event.new(type, stringify(msg), "claude")], state}

      {:ok, _} ->
        {:ok, [], state}

      {:error, reason} ->
        {:error, {:invalid_json, reason}}
    end
  end

  @impl true
  def encode(:initialize, state), do: {:ok, "", state}
  def encode(:initialized, state), do: {:ok, "", state}
  def encode({:start_session, _cwd}, state), do: {:ok, "", state}

  def encode({:resume, session_id}, state) do
    {:ok, user_line(%{"resume" => session_id, "content" => "resume"}), state}
  end

  def encode({:prompt, text}, state), do: encode({:prompt, text, []}, state)

  def encode({:prompt, text, attachments}, state) do
    {:ok,
     user_line(%{"content" => AgentDesk.Providers.Prompt.with_file_notes(text, attachments)}),
     state}
  end

  def encode(:interrupt, state) do
    {:ok, Jason.encode!(%{"type" => "control", "subtype" => "interrupt"}) <> "\n", state}
  end

  def encode({:configure_mcp, _path}, state), do: {:ok, "", state}
  def encode(_action, _state), do: {:error, :unsupported_action}

  defp user_line(fields) do
    Jason.encode!(%{
      "type" => "user",
      "message" => %{"role" => "user", "content" => fields["content"] || ""}
    }) <> "\n"
  end

  defp text_content(list) when is_list(list) do
    list
    |> Enum.map_join(fn
      %{"text" => text} -> text
      _ -> ""
    end)
  end

  defp text_content(_), do: ""

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
