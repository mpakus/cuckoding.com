defmodule AgentDesk.Providers.Cursor do
  @moduledoc """
  Cursor Agent ACP adapter. Shares ACP framing with OpenCode; owns Cursor extensions.
  """

  @behaviour AgentDesk.Providers.Adapter

  alias AgentDesk.Providers.ACP.Client
  alias AgentDesk.Providers.Capabilities
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Fixture
  alias AgentDesk.Providers.Probe

  @impl true
  def key, do: "cursor"

  @impl true
  def display_name, do: "Cursor"

  @impl true
  def capabilities do
    %Capabilities{
      key: key(),
      structured_events: true,
      multi_turn: true,
      resume: true,
      steer_active_turn: false,
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
  def probe(opts), do: Probe.probe(key(), "agent", opts)

  @impl true
  def command_spec(session, opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    if Fixture.enabled?(opts ++ [fixture: session.settings["fixture"]]) do
      {:ok,
       Fixture.command_spec(
         "acp",
         Keyword.merge(opts,
           cwd: cwd,
           peer_args: ["--vendor", "cursor"] ++ Keyword.get(opts, :peer_args, [])
         )
       )}
    else
      {:ok,
       %CommandSpec{executable: Keyword.get(opts, :executable, "agent"), args: ["acp"], cwd: cwd}}
    end
  end

  @impl true
  def init_decode, do: Client.new(key())

  @impl true
  def decode_line(line, state), do: Client.decode_line(state, line)

  @impl true
  def encode(action, state), do: Client.encode(state, action)
end
