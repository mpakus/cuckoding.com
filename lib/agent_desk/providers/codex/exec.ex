defmodule AgentDesk.Providers.Codex.Exec do
  @moduledoc """
  Codex `exec --json` one-shot fallback with reduced capabilities.
  """

  @behaviour AgentDesk.Providers.Adapter

  alias AgentDesk.Providers.Capabilities
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Event
  alias AgentDesk.Providers.Fixture
  alias AgentDesk.Providers.Probe

  defstruct []

  @impl true
  def key, do: "codex-exec"

  @impl true
  def display_name, do: "Codex (exec)"

  @impl true
  def capabilities do
    %Capabilities{
      key: key(),
      structured_events: true,
      multi_turn: false,
      resume: false,
      steer_active_turn: false,
      approvals: false,
      mcp_stdio: false,
      file_change_events: true,
      usage_events: true,
      structured_output: true,
      internal_a2a: true,
      safe_boundary_delivery: true
    }
  end

  @impl true
  def probe(opts), do: Probe.probe("codex", "codex", opts)

  @impl true
  def command_spec(session, opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    prompt = Keyword.get(opts, :prompt, session.settings["prompt"] || "hello")

    if Fixture.enabled?(opts ++ [fixture: session.settings["fixture"]]) do
      {:ok, Fixture.command_spec("codex-exec", Keyword.put(opts, :cwd, cwd))}
    else
      {:ok,
       %CommandSpec{
         executable: Keyword.get(opts, :executable, "codex"),
         args: ["exec", "--json", prompt],
         cwd: cwd
       }}
    end
  end

  @impl true
  def init_decode, do: %__MODULE__{}

  @impl true
  def decode_line(line, %__MODULE__{} = state) do
    case Jason.decode(line) do
      {:ok, %{"type" => "thread.started"} = msg} ->
        {:ok, [Event.new(:session_ready, %{"provider_session_id" => msg["thread_id"]}, "codex")],
         state}

      {:ok, %{"type" => "item.agent_message.delta"} = msg} ->
        {:ok, [Event.new(:message_delta, %{"text" => msg["delta"] || ""}, "codex")], state}

      {:ok, %{"type" => "turn.completed"} = msg} ->
        {:ok, [Event.new(:turn_completed, stringify(msg), "codex")], state}

      {:ok, %{"type" => "item.completed"} = msg} ->
        {:ok, [Event.new(:message_completed, stringify(msg), "codex")], state}

      {:ok, _} ->
        {:ok, [], state}

      {:error, reason} ->
        {:error, {:invalid_json, reason}}
    end
  end

  @impl true
  def encode(_action, state), do: {:ok, "", state}

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
