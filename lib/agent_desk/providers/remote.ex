defmodule AgentDesk.Providers.Remote do
  @moduledoc """
  Attachable agent with no child process.

  AgentDesk issues a capability token and writes per-session MCP config. The
  agent connects inbound over loopback MCP. This is not a public A2A gateway.
  """

  @behaviour AgentDesk.Providers.Adapter

  alias AgentDesk.Providers.Capabilities

  @impl true
  def key, do: "remote"

  @impl true
  def display_name, do: "Remote"

  @impl true
  def capabilities do
    %Capabilities{
      key: key(),
      structured_events: true,
      multi_turn: true,
      resume: true,
      mcp_stdio: true,
      usage_events: true,
      internal_a2a: true,
      safe_boundary_delivery: true,
      spawned: false
    }
  end

  @impl true
  def probe(_opts) do
    {:ok, %{key: key(), executable: "attach", version: "mcp", protocol: "attach"}}
  end

  @impl true
  def command_spec(_session, _opts), do: {:ok, :attach}

  @impl true
  def init_decode, do: %{}

  @impl true
  def decode_line(_line, state), do: {:ok, [], state}

  @impl true
  def encode(_action, state), do: {:ok, "", state}
end
