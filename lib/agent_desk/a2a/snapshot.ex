defmodule AgentDesk.A2A.Snapshot do
  @moduledoc """
  Generated human-readable status snapshots. Never proof of lease or task ownership.
  """

  alias AgentDesk.A2A.Directory
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope
  alias AgentDesk.Storage

  @spec write!(Scope.t()) :: String.t()
  def write!(%Scope{project: project} = scope) do
    dir = Storage.project_dir(project.id)
    File.mkdir_p!(dir)
    path = Path.join(dir, "status.md")
    File.write!(path, render(scope))
    path
  end

  @spec render(Scope.t()) :: String.t()
  def render(%Scope{project: project} = scope) do
    agents = Directory.list_agents(scope)
    leases = Manager.list_project(project.id)

    [
      "# AgentDesk status",
      "",
      "Project: #{project.name}",
      "",
      "## Agents",
      Enum.map_join(agents, "\n", fn card ->
        "- #{card.name} (#{card.availability}) skills=#{inspect(card.skills)}"
      end),
      "",
      "## Active leases",
      if(leases == [],
        do: "- none",
        else:
          Enum.map_join(leases, "\n", fn lease ->
            "- #{lease.mode} #{lease.resource_type}:#{lease.resource_key} owner=#{lease.agent_session_id}"
          end)
      ),
      ""
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end
end
