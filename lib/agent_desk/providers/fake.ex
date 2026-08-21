defmodule AgentDesk.Providers.Fake do
  @moduledoc """
  In-process test adapter used when a scripted ACP fixture is enough.
  """

  @behaviour AgentDesk.Providers.Adapter

  alias AgentDesk.Providers.ACP.Client
  alias AgentDesk.Providers.Capabilities
  alias AgentDesk.Providers.Fixture
  alias AgentDesk.Providers.Probe

  @impl true
  def key, do: "fake"

  @impl true
  def display_name, do: "Fake"

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
      file_change_events: true,
      usage_events: true,
      structured_output: true,
      internal_a2a: true,
      safe_boundary_delivery: true
    }
  end

  @impl true
  def probe(opts), do: Probe.probe(key(), "elixir", opts)

  @impl true
  def command_spec(_session, opts) do
    {:ok,
     Fixture.command_spec(
       "acp",
       Keyword.merge(opts, peer_args: ["--vendor", "fake"] ++ Keyword.get(opts, :peer_args, []))
     )}
  end

  @impl true
  def init_decode, do: Client.new(key())

  @impl true
  def decode_line(line, state), do: Client.decode_line(state, line)

  @impl true
  def encode(action, state), do: Client.encode(state, action)
end
