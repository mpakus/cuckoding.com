defmodule AgentDesk.Reconcile do
  @moduledoc """
  Startup recovery for sessions, leases, worktrees, ports, and tokens.

  Never kills an OS pid from `process_identity`; PID reuse would hit the wrong
  process. Provider Ports are closed only by the session worker that owns them.
  """

  alias AgentDesk.A2A
  alias AgentDesk.Agents
  alias AgentDesk.Projects.Project
  alias AgentDesk.Repo
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Security.Capability
  alias AgentDesk.Worktrees

  @spec project(Project.t()) :: :ok
  def project(%Project{} = project) do
    :ok = reconcile_durable_state(project.id)
    Worktrees.reconcile(project)
    AgentDesk.Containers.reconcile(project)
    :ok
  end

  defp reconcile_durable_state(project_id) do
    live_ids = live_session_ids(project_id)

    {:ok, :ok} =
      Repo.transaction(fn ->
        Agents.interrupt_orphans(project_id, live_ids)
        Capability.revoke_project(project_id, except: live_ids)
        Manager.expire_project(project_id, except: live_ids)
        A2A.expire_due_delegations(project_id)
        A2A.reconcile_project(project_id)
        :ok
      end)

    :ok
  end

  defp live_session_ids(project_id) do
    project_id
    |> Agents.list_sessions()
    |> Enum.filter(fn session ->
      match?({:ok, _pid}, AgentDesk.Providers.SessionWorker.fetch(session.id))
    end)
    |> Enum.map(& &1.id)
  end
end
