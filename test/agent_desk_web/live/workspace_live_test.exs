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
    assert has_element?(view, "#task-conversation")
    assert has_element?(view, "#message-panel")
    assert html =~ "No active leases"
  end
end
