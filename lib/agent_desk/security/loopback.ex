defmodule AgentDesk.Security.Loopback do
  @moduledoc """
  Control-plane listeners must bind loopback only.
  """

  @loopback [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}]

  @spec endpoint_ip() :: tuple() | nil
  def endpoint_ip do
    http = Application.get_env(:agent_desk, AgentDeskWeb.Endpoint)[:http] || []
    Keyword.get(http, :ip)
  end

  @spec loopback?(tuple() | nil) :: boolean()
  def loopback?(ip) when ip in @loopback, do: true
  def loopback?(_), do: false

  @spec assert!() :: :ok
  def assert! do
    ip = endpoint_ip()

    if loopback?(ip) do
      :ok
    else
      raise "AgentDesk HTTP listener must bind loopback, got: #{inspect(ip)}"
    end
  end
end
