defmodule AgentDesk.Providers.SessionTest do
  use AgentDesk.DataCase

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Delivery
  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Providers.Codex.Exec
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Providers.Transcript
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  setup do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    %{project: project, scope: Scope.for_project(project)}
  end

  test "two sessions run concurrently and closing a tab does not terminate the worker", %{
    scope: scope
  } do
    {:ok, one} = Providers.start_session(scope, %{provider: "fake", display_name: "One"})
    {:ok, two} = Providers.start_session(scope, %{provider: "cursor", display_name: "Two"})

    assert wait_until(fn -> Repo.get!(Agents.Session, one.id).provider_session_id end)
    assert wait_until(fn -> Repo.get!(Agents.Session, two.id).provider_session_id end)
    assert {:ok, pid} = SessionWorker.fetch(one.id)

    {:ok, hidden} = Agents.hide_tab(one)
    assert Map.get(hidden.settings, "tab_open") == false
    assert Process.alive?(pid)
    assert SessionWorker.fetch(one.id) == {:ok, pid}
    assert length(Agents.visible_sessions(scope)) == 1
  end

  test "session history and provider id survive worker restart", %{scope: scope} do
    {:ok, session} = Providers.start_session(scope, %{provider: "fake", display_name: "Resume"})
    ready = wait_until(fn -> Repo.get!(Agents.Session, session.id).provider_session_id end)
    assert ready

    Providers.stop_worker(session.id)
    session = Repo.get!(Agents.Session, session.id)
    assert session.provider_session_id

    {:ok, _pid} = Providers.resume_session(session)

    resumed =
      wait_until(fn ->
        updated = Repo.get!(Agents.Session, session.id)
        updated.provider_session_id == session.provider_session_id && updated.status == "idle"
      end)

    assert resumed
    assert Transcript.read(session.project_id, session.id) != []
  end

  test "pending A2A inbox is injected at a safe boundary", %{scope: scope, project: project} do
    {:ok, sender} = Agents.create_session(scope, %{provider: "fake", display_name: "Sender"})
    {:ok, session} = Providers.start_session(scope, %{provider: "fake", display_name: "Inbox"})
    wait_until(fn -> Repo.get!(Agents.Session, session.id).provider_session_id end)

    {:ok, context} = A2A.create_context(Scope.for_agent(project, sender), %{title: "Coord"})

    {:ok, _message} =
      A2A.send_direct_message(Scope.for_agent(project, sender), %{
        context_id: context.id,
        recipient_agent_id: session.id,
        body: "please pick this up",
        idempotency_key: "inbox-1"
      })

    SessionWorker.prompt(session.id, "continue")

    acked =
      wait_until(fn ->
        Repo.get_by(Delivery, agent_session_id: session.id, state: "acknowledged")
      end)

    assert acked
  end

  test "codex exec decoder understands one-shot JSONL" do
    state = Exec.init_decode()
    {:ok, events, _} = Exec.decode_line(~s({"type":"thread.started","thread_id":"t1"}), state)
    assert hd(events).type == :session_ready
  end
end
