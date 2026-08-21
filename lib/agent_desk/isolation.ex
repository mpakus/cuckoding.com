defmodule AgentDesk.Isolation do
  @moduledoc """
  Per-agent isolation names for databases, Compose projects, and ports.
  """

  alias AgentDesk.Agents.Session
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope

  @port_range 41_000..41_199

  @spec test_database(Session.t()) :: String.t()
  def test_database(%Session{id: id}), do: "agentdesk_test_" <> short(id)

  @spec test_schema(Session.t()) :: String.t()
  def test_schema(%Session{id: id}), do: "agent_" <> short(id)

  @spec compose_project(Session.t()) :: String.t()
  def compose_project(%Session{id: id}), do: "agentdesk_" <> short(id)

  @spec allocate_port(Scope.t()) :: {:ok, integer()} | {:error, term()}
  def allocate_port(%Scope{} = scope) do
    used =
      scope.project.id
      |> Manager.list_project()
      |> Enum.filter(&(&1.resource_type == "port"))
      |> MapSet.new(& &1.resource_key)

    case Enum.find(@port_range, fn n -> not MapSet.member?(used, "tcp:#{n}") end) do
      nil ->
        {:error, :ports_exhausted}

      number ->
        key = "tcp:#{number}"

        case Manager.claim(scope, [%{"type" => "port", "key" => key, "mode" => "exclusive"}],
               reason: "session port"
             ) do
          {:ok, _} -> {:ok, number}
          error -> error
        end
    end
  end

  defp short(id) do
    id |> String.replace("-", "") |> String.slice(0, 12)
  end
end
