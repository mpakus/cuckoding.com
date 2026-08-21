defmodule AgentDeskWeb.WorkspaceLiveTest do
  use AgentDeskWeb.ConnCase

  import Phoenix.LiveViewTest

  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Scope

  test "renders the workspace shell", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "AgentDesk"
    assert has_element?(view, "#open-project-form")
    assert render(view) =~ "No projects opened yet."
  end

  test "opens a git repository from the form", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#open-project-form", path: repo)
    |> render_submit()

    html = render(view)
    assert html =~ Path.basename(repo)
    assert html =~ "Project runtime started"
  after
    :ok
  end

  test "shows an error when the path is not a git repository", %{conn: conn} do
    dir = Path.join(System.tmp_dir!(), "not-git-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#open-project-form", path: dir)
    |> render_submit()

    assert render(view) =~ "Open a Git repository"
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
      provider: "fake",
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

    view
    |> form("#start-session-form", provider: "fake", display_name: "Atlas")
    |> render_submit()

    assert render(view) =~ "Atlas"
    [session] = Agents.visible_sessions(Scope.for_project(project))
    assert {:ok, pid} = SessionWorker.fetch(session.id)

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
    assert has_element?(view, "#delegation-inbox")
    assert has_element?(view, "#resource-leases")
    assert has_element?(view, "#artifact-panel")
    assert has_element?(view, "#merge-queue")
    assert has_element?(view, "#task-conversation")
    assert has_element?(view, "#create-task")
    assert has_element?(view, "#run-workflow")
    assert has_element?(view, "#message-panel")
    assert has_element?(view, "#worktree-panel")
    assert has_element?(view, "#search-panel")
    assert has_element?(view, "#rebuild-search")
    assert has_element?(view, "#sync-panel")
    assert has_element?(view, "#export-sync")
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

    view |> element("#close-project-#{b.id}") |> render_click()
    view |> element("#confirm-close-#{b.id}") |> render_click()

    assert AgentDesk.Projects.Runtime.fetch(b.id) == {:error, :not_started}
    assert {:ok, _} = AgentDesk.Projects.Runtime.fetch(a.id)
  end

  test "starts a remote attach session and shows usage totals", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "SDK"
    assert has_element?(view, "#usage-panel")

    view
    |> form("#start-session-form", provider: "remote", display_name: "Offbox")
    |> render_submit()

    assert has_element?(view, "#remote-connect")

    assert AgentDesk.DataCase.wait_until(fn ->
             sessions = Agents.visible_sessions(Scope.for_project(project))
             match?([%{provider: "remote"}], sessions)
           end)
  end
end
