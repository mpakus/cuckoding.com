defmodule AgentDesk.Providers.RemoteTest do
  use AgentDesk.DataCase

  alias AgentDesk.A2A
  alias AgentDesk.A2A.AgentCard
  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Providers.MCPInjection
  alias AgentDesk.Providers.SDK
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Repo
  alias AgentDesk.Scope
  alias AgentDesk.Usage

  setup do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    %{project: project, scope: Scope.for_project(project)}
  end

  test "attach session registers a card without spawning a port", %{scope: scope} do
    {:ok, session} =
      Providers.start_session(scope, %{provider: "remote", display_name: "Offbox"})

    ready =
      wait_until(fn ->
        updated = Repo.get!(Agents.Session, session.id)
        updated.provider_session_id && updated
      end)

    assert ready.status in ["idle", "working"]
    assert ready.process_identity["mode"] == "attach"

    card =
      wait_until(fn ->
        Repo.get_by(AgentCard, agent_session_id: session.id)
      end)

    assert card
    assert SessionWorker.fetch(session.id) != {:error, :not_started}

    path = MCPInjection.connect_env_path(ready)
    assert File.exists?(path)
    body = File.read!(path)
    [_, token] = Regex.run(~r/AGENTDESK_CAPABILITY_TOKEN=([^\s]+)/, body)
    card = Repo.get_by(AgentCard, agent_session_id: session.id)
    refute card.description =~ token
    refute card.name =~ token
  end

  test "prompts for attach sessions land in the durable inbox", %{scope: scope} do
    {:ok, session} =
      Providers.start_session(scope, %{provider: "remote", display_name: "Offbox"})

    wait_until(fn -> Repo.get!(Agents.Session, session.id).provider_session_id end)
    assert :ok = SessionWorker.prompt(session.id, "hello remote")

    inbox =
      wait_until(fn ->
        deliveries =
          A2A.inbox(Scope.for_agent(scope.project, Repo.get!(Agents.Session, session.id)))

        deliveries != [] && deliveries
      end)

    assert Enum.any?(inbox, fn delivery ->
             delivery.message && delivery.message.body =~ "hello remote"
           end)
  end

  test "sdk adapter records usage samples from fixture turns", %{scope: scope} do
    {:ok, session} = Providers.start_session(scope, %{provider: "sdk", display_name: "SDK"})
    wait_until(fn -> Repo.get!(Agents.Session, session.id).provider_session_id end)
    assert :ok = SessionWorker.prompt(session.id, "hello")

    assert wait_until(fn ->
             Usage.summary(scope.project)["output_tokens"] > 0
           end)
  end

  test "sdk command_spec rejects path traversal when fixtures are off" do
    session = %AgentDesk.Agents.Session{settings: %{"sdk_executable" => "../bin/evil"}}
    assert {:error, :invalid_executable} = SDK.command_spec(session, fixture: false)
  end
end
