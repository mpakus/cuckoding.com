defmodule AgentDeskWeb.WorkspaceLiveTest do
  use AgentDeskWeb.ConnCase

  import Phoenix.LiveViewTest

  alias AgentDesk.GitRepo
  alias AgentDesk.Projects

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
end
