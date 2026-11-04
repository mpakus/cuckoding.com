defmodule Boss.Agents.NetworkPolicy do
  @moduledoc """
  Versioned implementation-only command networking; never supplied by a model.

  Public destinations are fixed package hosts. Local binding additionally permits
  broader local/private networking; it is not a port-specific loopback rule.
  The Codex command proxy does not govern hosted tools, apps or MCP connections.
  """

  @domains ~w(127.0.0.1 builds.hex.pm github.com hex.pm localhost registry.npmjs.org release-assets.githubusercontent.com repo.hex.pm)
  @profile %{
    "version" => 1,
    "network_access" => true,
    "proxy" => true,
    "allow_local_binding" => true,
    "domains" => @domains
  }

  def current, do: 1
  def profile(version) when version in [nil, 0], do: nil
  def profile(1), do: @profile
  def valid?(profile), do: profile == @profile

  def args(profile) do
    unless valid?(profile), do: raise(ArgumentError, "invalid implementation network policy")

    domains = Enum.map_join(@domains, ",", &~s("#{&1}"="allow"))

    [
      "--config",
      "sandbox_workspace_write.network_access=true",
      "--config",
      "features.network_proxy.enabled=true",
      "--config",
      "features.network_proxy.domains={#{domains}}",
      "--config",
      "features.network_proxy.allow_local_binding=true"
    ]
  end
end
