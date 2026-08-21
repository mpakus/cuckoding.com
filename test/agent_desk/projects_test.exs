defmodule AgentDesk.ProjectsTest do
  use AgentDesk.DataCase

  alias AgentDesk.Events
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Projects.Runtime

  setup do
    repo = GitRepo.tmp_repo!()
    on_exit(fn -> File.rm_rf(repo) end)
    %{repo: repo}
  end

  test "opens a git repository, records an event, and starts a runtime", %{repo: repo} do
    assert {:ok, project} = Projects.open_project(repo)
    assert project.canonical_path == Path.expand(repo)
    assert project.vcs_type == "git"
    assert {:ok, _pid} = Runtime.fetch(project.id)

    [event] = Events.list_for_project(project.id)
    assert event.type == "project.opened"
    assert event.source == "projects"

    on_exit(fn -> AgentDesk.Projects.Supervisor.stop_runtime(project.id) end)
  end

  test "reopening the same path updates last_opened_at instead of duplicating", %{repo: repo} do
    {:ok, first} = Projects.open_project(repo)
    {:ok, second} = Projects.open_project(repo)

    assert first.id == second.id
    assert DateTime.compare(second.last_opened_at, first.last_opened_at) in [:gt, :eq]
    assert length(Projects.list_recent()) == 1

    on_exit(fn -> AgentDesk.Projects.Supervisor.stop_runtime(first.id) end)
  end

  test "rejects a directory that is not a git repository" do
    dir = Path.join(System.tmp_dir!(), "not-git-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    assert Projects.open_project(dir) == {:error, :not_a_git_repository}
  after
    :ok
  end

  test "restore_last_opened starts the runtime for the most recent project", %{repo: repo} do
    {:ok, project} = Projects.open_project(repo)
    :ok = AgentDesk.Projects.Supervisor.stop_runtime(project.id)

    assert {:ok, restored} = Projects.restore_last_opened()
    assert restored.id == project.id
    assert {:ok, pid} = Runtime.fetch(project.id)
    assert Process.alive?(pid)
  end

  test "close_project stops the runtime and appends a closed event", %{repo: repo} do
    {:ok, project} = Projects.open_project(repo)
    assert :ok = Projects.close_project(project)
    assert Runtime.fetch(project.id) == {:error, :not_started}

    types = project.id |> Events.list_for_project() |> Enum.map(& &1.type)
    assert "project.closed" in types
  end
end
