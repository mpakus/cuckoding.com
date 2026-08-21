defmodule AgentDesk.Security.Permissions do
  @moduledoc """
  Per-session permission profiles for Agent Hub tools.
  """

  alias AgentDesk.Agents.Session

  @observer ~w(
    hub_heartbeat
    hub_list_agents
    hub_get_agent_card
    hub_find_agents
    hub_list_tasks
    hub_get_task
    hub_list_delegations
    hub_list_resources
    hub_list_inbox
    hub_get_artifact
    hub_list_merge_queue
    hub_list_task_graph
    hub_list_workflows
    hub_list_roles
    hub_subscribe_task
    project_search
    memory_recall
  )

  @spec allowed?(Session.t(), String.t()) :: boolean()
  def allowed?(%Session{} = session, tool) when is_binary(tool) do
    case tools_for(profile(session)) do
      :all -> true
      allowed -> tool in allowed
    end
  end

  @spec profile(Session.t()) :: String.t()
  def profile(%Session{settings: settings}) do
    settings["permission_profile"] || "default"
  end

  @spec tools_for(String.t()) :: :all | [String.t()]
  def tools_for("observer"), do: @observer
  def tools_for("restricted"), do: @observer
  def tools_for(_profile), do: :all

  @spec filter_tools(Session.t(), [String.t()]) :: [String.t()]
  def filter_tools(%Session{} = session, tools) do
    case tools_for(profile(session)) do
      :all -> tools
      allowed -> Enum.filter(tools, &(&1 in allowed))
    end
  end
end
