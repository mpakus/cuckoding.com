defmodule AgentDesk.Security.CapabilityTest do
  use AgentDesk.DataCase

  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Scope
  alias AgentDesk.Security.Capability

  setup do
    repo = GitRepo.tmp_repo!("agentdesk-capability")
    {:ok, project} = Projects.open_project(repo)
    on_exit(fn -> Projects.Supervisor.stop_runtime(project.id) end)

    {:ok, session} =
      Agents.create_session(Scope.for_project(project), %{
        provider: "fake",
        display_name: "Capability holder",
        status: "idle"
      })

    %{session: session}
  end

  test "authentication rejects inactive sessions even before token expiry", %{session: session} do
    {:ok, token, session} = Capability.issue(session)
    assert {:ok, _session} = Capability.authenticate(token)

    assert {:ok, _session} = Agents.update_session(session, %{status: "interrupted"})
    assert Capability.authenticate(token) == {:error, :unauthorized}
  end

  test "authentication rejects capabilities without an expiry", %{session: session} do
    {:ok, token, session} = Capability.issue(session)
    assert {:ok, _session} = Agents.update_session(session, %{capability_expires_at: nil})

    assert Capability.authenticate(token) == {:error, :unauthorized}
  end
end
