defmodule AgentDeskWeb.WorkspaceLiveTest do
  use AgentDeskWeb.ConnCase

  import Phoenix.LiveViewTest

  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Providers.Event
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Scope

  test "renders the workspace shell", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Cuckoding"
    assert has_element?(view, "#open-project")
    assert has_element?(view, "#recent-projects")
    assert has_element?(view, "#agent-grove")
    assert has_element?(view, "#first-run")
    assert render(view) =~ "Idle until a session starts"
    assert render(view) =~ "No projects opened yet."
    assert render(view) =~ "Select a Git repository"
    assert has_element?(view, "#onboard-next")
    assert has_element?(view, "#shortcuts-help")

    view |> element("#onboard-next") |> render_click()
    assert render(view) =~ "step 2 of 10"
    refute has_element?(view, "#theme-toggle")
    refute html =~ "paste a path"
    refute has_element?(view, "#project-path")
    refute has_element?(view, "#open-project-form")
    refute html =~ "phx:set-theme"
  end

  test "choose folder asks the native picker", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Choose folder"
    assert has_element?(view, "#choose-repo")

    view
    |> element("#choose-repo")
    |> render_click()

    assert_push_event(view, "tauri_command", %{
      command: "dialog_open",
      payload: %{directory: true, title: "Choose a Git repository", defaultPath: _}
    })
  end

  test "reports a native picker failure", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = render_click(view, "picker_failed", %{"error" => "denied"})
    assert html =~ "Could not open the macOS folder picker."
  end

  test "explains why a provider session could not start", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    html = render_click(view, "start_session", %{"provider" => "nope", "display_name" => "X"})
    assert html =~ "Could not save that session."
  end

  test "lists recent projects and opens one from recents", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    :ok = Projects.close_project(project)

    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ project.name
    assert has_element?(view, "#recent-#{project.id}")
    assert has_element?(view, "#check-recent-#{project.id}")

    view
    |> element("#open-recent-#{project.id}")
    |> render_click()

    html = render(view)
    assert html =~ project.name
    assert html =~ "Opened #{project.name}"
    assert_patch(view, ~p"/projects/#{project.id}")

    AgentDesk.Projects.Supervisor.stop_runtime(project.id)
  end

  test "check again re-validates a recent project", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    :ok = Projects.close_project(project)

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#check-recent-#{project.id}")
    |> render_click()

    html = render(view)
    assert html =~ "Checked #{project.name}. Repository is still valid."
    assert_patch(view, ~p"/projects/#{project.id}")

    AgentDesk.Projects.Supervisor.stop_runtime(project.id)
  end

  test "check again shows a missing-folder error and can remove from recents", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    :ok = Projects.close_project(project)
    File.rm_rf!(repo)

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ project.name

    view
    |> element("#check-recent-#{project.id}")
    |> render_click()

    html = render(view)
    assert html =~ "That folder is gone. It may have been moved or deleted."
    assert has_element?(view, "#forget-recent-#{project.id}")

    view
    |> element("#forget-recent-#{project.id}")
    |> render_click()

    view
    |> element("#confirm-forget-#{project.id}")
    |> render_click()

    html = render(view)
    refute has_element?(view, "#recent-#{project.id}")
    assert html =~ "Removed #{project.name} from recents."
  end

  test "shows an opened project from a patched URL", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ project.name
    assert has_element?(view, "#recent-projects")

    AgentDesk.Projects.Supervisor.stop_runtime(project.id)
  end

  test "restores the last opened project from the index", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)

    {:ok, view, _html} = live(conn, ~p"/")
    assert_patch(view, ~p"/projects/#{project.id}")
    assert render(view) =~ project.name

    AgentDesk.Projects.Supervisor.stop_runtime(project.id)
  end

  test "saves a role and starts a session with it", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#tab-new") |> render_click()

    assert has_element?(view, "#session-role")
    assert has_element?(view, "#save-role-form")
    assert has_element?(view, "#container-opt-in")

    view
    |> form("#save-role-form",
      name: "auditor",
      description: "Audits handoffs",
      permission_profile: "restricted",
      prompt: "HIDDEN_PROMPT_TOKEN"
    )
    |> render_submit()

    html = render(view)
    assert html =~ "auditor"

    auditor = Enum.find(AgentDesk.Roles.list(project), &(&1.name == "auditor"))

    view
    |> form("#start-session-form",
      provider: "codex",
      display_name: "Audit",
      role_id: auditor.id
    )
    |> render_submit()

    assert render(view) =~ "auditor"
    [session] = Agents.visible_sessions(Scope.for_project(project))
    assert session.role == "auditor"
    assert session.settings["permission_profile"] == "restricted"
  end

  test "creates a session tab and closing it leaves the worker running", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#tab-new") |> render_click()

    view
    |> form("#start-session-form", provider: "codex", display_name: "Atlas")
    |> render_submit()

    assert render(view) =~ "Atlas"
    [session] = Agents.visible_sessions(Scope.for_project(project))
    assert {:ok, pid} = SessionWorker.fetch(session.id)
    assert has_element?(view, "#isolation-card")
    assert render(view) =~ AgentDesk.Isolation.test_database(session)
    assert File.exists?(Path.join(AgentDesk.Isolation.dir(session), "postgres.schema.sql"))

    view |> element("#close-tab-#{session.id}") |> render_click()
    refute has_element?(view, "#tab-#{session.id}")
    assert Process.alive?(pid)
  end

  test "renders an approval card for a provider permission request", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)

    {:ok, session} =
      Providers.start_session(
        Scope.for_project(project),
        %{provider: "fake", display_name: "Approver"},
        peer_args: ["--approval"]
      )

    assert AgentDesk.DataCase.wait_until(fn ->
             AgentDesk.Repo.get!(AgentDesk.Agents.Session, session.id).provider_session_id
           end)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#tab-#{session.id}") |> render_click()
    view |> form("#prompt-composer", prompt: "go") |> render_submit()

    assert AgentDesk.DataCase.wait_until(fn ->
             html = render(view)
             html =~ "approval-card" or html =~ "Allow"
           end)
  end

  test "shows coordination panels for agents, delegations, leases, and artifacts", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(view, "#agents-directory")
    assert has_element?(view, "#agent-filters")
    assert has_element?(view, "#agent-filter-all")
    assert has_element?(view, "#delegation-inbox")
    assert has_element?(view, "#resource-leases")
    assert has_element?(view, "#artifact-panel")
    assert has_element?(view, "#merge-queue")
    assert has_element?(view, "#task-conversation")
    assert has_element?(view, "#split-work")
    assert has_element?(view, "#create-task")
    assert has_element?(view, "#run-workflow")
    assert has_element?(view, "#message-panel")
    assert has_element?(view, "#worktree-panel")
    assert has_element?(view, "#search-panel")
    assert has_element?(view, "#rebuild-search")
    assert has_element?(view, "#sync-panel")
    assert has_element?(view, "#export-sync")
    assert has_element?(view, "#tab-dashboard")
    assert has_element?(view, "#tab-new")
    assert has_element?(view, "#session-tabs")
    view |> element("#tab-new") |> render_click()
    assert has_element?(view, "#new-session")
    assert has_element?(view, "#shared-opt-in")
    assert has_element?(view, "#sidebar-queues")
    assert has_element?(view, "#sidebar-tasks")
    assert has_element?(view, "#sidebar-agents")
    assert has_element?(view, "#sidebar-delegations")
    assert has_element?(view, "#sidebar-handoffs")
    assert has_element?(view, "#sidebar-search")
    assert html =~ "Isolated worktree"
    assert html =~ "Automatic eligible peer"
    assert html =~ "No active leases"
  end

  test "exports a team sync bundle from the workspace", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view |> element("#export-sync") |> render_click()
    assert has_element?(view, "#sync-path")
    assert render(view) =~ "bundle.json"
  end

  test "shows live badges for two open projects and overlap previews", %{conn: conn} do
    repo_a = GitRepo.tmp_repo!()
    repo_b = GitRepo.tmp_repo!()
    {:ok, a} = Projects.open_project(repo_a)
    {:ok, b} = Projects.open_project(repo_b)
    scope = Scope.for_project(a)
    {:ok, alice} = Agents.create_session(scope, %{provider: "fake", display_name: "Alice"})
    {:ok, bob} = Agents.create_session(scope, %{provider: "fake", display_name: "Bob"})

    assert {:ok, _} =
             AgentDesk.Resources.Manager.claim(
               Scope.for_agent(a, alice),
               [%{"type" => "directory", "key" => "lib", "mode" => "shared"}],
               reason: "browse"
             )

    assert {:ok, _} =
             AgentDesk.Resources.Manager.claim(
               Scope.for_agent(a, bob),
               [%{"type" => "file", "key" => "lib/app.ex", "mode" => "shared"}],
               reason: "read"
             )

    {:ok, view, html} = live(conn, ~p"/projects/#{a.id}")
    assert html =~ "live"
    assert has_element?(view, "#close-project-#{b.id}")
    assert render(view) =~ "overlaps"
    assert render(view) =~ "Send message"
    assert render(view) =~ "Wait and retry"
    assert render(view) =~ "Request release"

    view |> element("#close-project-#{b.id}") |> render_click()
    view |> element("#confirm-close-#{b.id}") |> render_click()

    assert AgentDesk.Projects.Runtime.fetch(b.id) == {:error, :not_started}
    assert {:ok, _} = AgentDesk.Projects.Runtime.fetch(a.id)
  end

  test "starts a remote attach session and shows usage totals", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "ACP Registry"
    assert has_element?(view, "#usage-panel")
    view |> element("#tab-new") |> render_click()
    assert has_element?(view, "#start-session-form")

    view
    |> form("#start-session-form", provider: "remote", display_name: "Offbox")
    |> render_submit()

    assert has_element?(view, "#remote-connect")

    assert AgentDesk.DataCase.wait_until(fn ->
             sessions = Agents.visible_sessions(Scope.for_project(project))
             match?([%{provider: "remote"}], sessions)
           end)
  end

  test "installs an ACP registry agent and starts a session", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view |> element("#view-registry") |> render_click()
    assert has_element?(view, "#acp-registry")
    assert render(view) =~ "Codex"

    view |> element("#registry-install-cline") |> render_click()
    assert has_element?(view, "#registry-use-cline")

    view |> element("#registry-use-cline") |> render_click()
    html = render(view)
    assert html =~ "Cline"
    assert has_element?(view, "#session-tabs")
  end

  test "shows sqlite and xerj analytics", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view |> element("#tab-dashboard") |> render_click()
    html = render(view)
    assert has_element?(view, "#agent-analytics")
    assert html =~ "SQLite"
    assert html =~ "Runtime memory"
    assert html =~ "XERJ"
  end

  test "agent directory can message, delegate, and request review", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, alice} = Agents.create_session(scope, %{provider: "fake", display_name: "Alice"})
    {:ok, bob} = Agents.create_session(scope, %{provider: "fake", display_name: "Bob"})

    {:ok, _} =
      AgentDesk.A2A.register_card(Scope.for_agent(project, alice), %{
        name: "Alice",
        description: "Reviewer",
        skills: [%{"id" => "review"}]
      })

    {:ok, _} =
      AgentDesk.A2A.register_card(Scope.for_agent(project, bob), %{
        name: "Bob",
        description: "Implementer",
        skills: [%{"id" => "implement"}]
      })

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")
    assert html =~ "Delegate task"
    assert html =~ "Request review"
    assert html =~ "fake"
    assert has_element?(view, "#status-live")
    assert has_element?(view, "#agent-filter-review")
    assert has_element?(view, "#agent-filter-implement")
    assert has_element?(view, "#agent-card-#{alice.id}")
    assert has_element?(view, "#agent-card-#{bob.id}")
    assert render(view) =~ "assigned"

    view |> element("#agent-filter-review") |> render_click()
    assert has_element?(view, "#agent-card-#{alice.id}")
    refute has_element?(view, "#agent-card-#{bob.id}")

    view |> element("#agent-filter-all") |> render_click()
    assert has_element?(view, "#agent-card-#{bob.id}")

    view
    |> element(~s(button[phx-click="message_agent"][phx-value-id="#{bob.id}"]))
    |> render_click()

    assert render(view) =~ "Hello from Alice" or render(view) =~ "Message queued"

    view |> element("#open-agent-#{bob.id}") |> render_click()
    assert has_element?(view, "#tab-#{bob.id}[aria-selected=true]")
  end

  test "saves shortcuts and lists project areas in the sidebar", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(view, "#sidebar-nav")
    assert has_element?(view, "#shortcuts-help")
    assert html =~ "Tasks"
    assert html =~ "Handoffs"

    view
    |> form("#shortcut-form", send: "Control+Enter")
    |> render_submit()

    assert render(view) =~ "Control+Enter"
  end

  test "rejects a delegation with a reason", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, alice} = Agents.create_session(scope, %{provider: "fake", display_name: "Alice"})
    {:ok, bob} = Agents.create_session(scope, %{provider: "fake", display_name: "Bob"})
    alice_scope = Scope.for_agent(project, alice)

    {:ok, context} = AgentDesk.A2A.create_context(alice_scope, %{title: "Auth"})

    {:ok, task} =
      AgentDesk.A2A.create_task(alice_scope, context, %{
        title: "Add magic link",
        metadata: %{"skills" => ["elixir"]}
      })

    {:ok, _delegation} =
      AgentDesk.A2A.propose_delegation(alice_scope, %{
        task_id: task.id,
        to_agent_id: bob.id,
        reason: "Please implement",
        idempotency_key: "ui-reject-1"
      })

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")
    assert html =~ "Reject with reason"
    assert html =~ "elixir"

    view |> element("#tab-#{bob.id}") |> render_click()

    view
    |> form(~s(#delegation-inbox form[phx-submit="reject_delegation"]), reason: "too busy")
    |> render_submit()

    html = render(view)
    assert html =~ "too busy"
    assert html =~ "rejected"
  end

  test "creates a task with isolation and provider metadata", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view
    |> form("#create-task",
      title: "Ship auth",
      provider: "codex",
      isolated: "true",
      permission_profile: "restricted",
      skills: "elixir,liveview",
      auto_recipient: "true"
    )
    |> render_submit()

    html = render(view)
    assert html =~ "Ship auth"
    [task] = AgentDesk.A2A.list_tasks(Scope.for_project(project))
    assert task.metadata["provider"] == "codex"
    assert task.metadata["isolated"] == true
    assert task.metadata["permission_profile"] == "restricted"
    assert "elixir" in task.metadata["skills"]
  end

  test "splits work across existing specialist sessions", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)

    {:ok, lead} =
      Agents.create_session(scope, %{provider: "fake", display_name: "Lead", role: "lead"})

    {:ok, _backend} =
      Agents.create_session(scope, %{provider: "fake", display_name: "Backend", role: "backend"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view
    |> form("#split-work",
      goal: "Ship billing",
      lead_session_id: lead.id,
      lanes: ["backend"]
    )
    |> render_submit()

    html = render(view)
    assert html =~ "Ship billing"
    assert html =~ "Backend"
    assert html =~ "0/1 lanes done"
    assert html =~ "review waiting"

    parent =
      Enum.find(
        AgentDesk.A2A.list_tasks(scope),
        &(&1.metadata["orchestration"]["kind"] == "parent")
      )

    assert has_element?(view, "#task-group-#{parent.id}")
  end

  test "starts a session from the new-session control", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(view, "#tab-new")

    view |> element("#tab-new") |> render_click()
    assert has_element?(view, "#new-session")

    view
    |> form("#start-session-form", provider: "codex", display_name: "Nova")
    |> render_submit()

    html = render(view)
    assert html =~ "Nova"
    assert has_element?(view, "#session-tabs")
    assert html =~ "desk-tab-active"
  end

  test "puts each agent in its own tab", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, alice} = Agents.create_session(scope, %{provider: "fake", display_name: "Alice"})
    {:ok, bob} = Agents.create_session(scope, %{provider: "fake", display_name: "Bob"})
    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "Dashboard"
    assert has_element?(view, "#tab-dashboard")
    assert has_element?(view, "#tab-#{alice.id}")
    assert has_element?(view, "#tab-#{bob.id}")
    assert html =~ "desk-tab-dot"
    assert has_element?(view, "#close-tab-#{alice.id}")
    assert has_element?(view, "#session-tab-scroll")

    view |> element("#tab-#{bob.id}") |> render_click()
    assert has_element?(view, "#tab-#{bob.id}[aria-selected=true]")

    view |> element("#sidebar-agent-#{alice.id}") |> render_click()
    assert has_element?(view, "#tab-#{alice.id}[aria-selected=true]")

    view |> element("#tab-dashboard") |> render_click()
    assert has_element?(view, "#tab-dashboard[aria-selected=true]")
    assert has_element?(view, "#agent-analytics")
  end

  test "disambiguates duplicate agent tab names", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, first} = Agents.create_session(scope, %{provider: "fake", display_name: "Nova"})
    {:ok, second} = Agents.create_session(scope, %{provider: "fake", display_name: "Nova"})
    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(view, "#tab-#{first.id}")
    assert has_element?(view, "#tab-#{second.id}")
    assert html =~ String.slice(first.id, 0, 4)
    assert html =~ String.slice(second.id, 0, 4)
  end

  test "groups streamed agent tokens into one activity card", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, session} = Agents.create_session(scope, %{provider: "fake", display_name: "mtv2"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#tab-#{session.id}") |> render_click()

    send(
      view.pid,
      {:session_activity, session.id, [Event.new(:message_delta, %{"text" => "from"}, "codex")],
       "working", nil}
    )

    send(
      view.pid,
      {:session_activity, session.id,
       [
         Event.new(:message_delta, %{"text" => "the"}, "codex"),
         Event.new(:message_delta, %{"text" => "picker"}, "codex")
       ], "working", nil}
    )

    html = render(view)
    assert html =~ "from the picker"
    assert html |> :binary.matches("desk-activity-message_delta") |> length() == 1
  end

  test "prompt composer accepts file attachments", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, session} = Agents.create_session(scope, %{provider: "fake", display_name: "files"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#tab-#{session.id}") |> render_click()

    assert has_element?(view, "#prompt-composer")
    assert render(view) =~ "Attach"
    assert render(view) =~ "Paste or drop"
  end

  test "opens a dedicated handoff review screen", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view |> render_click("review_handoff", %{})
    assert has_element?(view, "#handoff-review")
    assert render(view) =~ "Handoff review"
  end
end
