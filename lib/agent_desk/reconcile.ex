defmodule AgentDesk.Reconcile do
  @moduledoc """
  Startup recovery for sessions, leases, worktrees, ports, and tokens.

  Never kills an OS pid from `process_identity`; PID reuse would hit the wrong
  process. Provider Ports are closed only by the session worker that owns them.
  """

  alias AgentDesk.A2A
  alias AgentDesk.Agents
  alias AgentDesk.Projects.Project
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Security.Capability
  alias AgentDesk.Worktrees

  @spec project(Project.t()) :: :ok
  def project(%Project{} = project) do
    Agents.interrupt_orphans(project.id)
    Manager.expire_due(project.id)
    A2A.expire_due_delegations(project.id)
    Capability.expire_due(project.id)
    Worktrees.reconcile(project)
    AgentDesk.Containers.reconcile(project)
    :ok
  end
end
