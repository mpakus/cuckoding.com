defmodule AgentDesk.ProjectsTest do
  use AgentDesk.DataCase

  alias AgentDesk.Events
  alias AgentDesk.GitRepo
  alias AgentDesk.Paths
  alias AgentDesk.Projects
  alias AgentDesk.Projects.Project
  alias AgentDesk.Projects.Runtime

  setup do
    repo = GitRepo.tmp_repo!()
    {:ok, canonical} = Paths.canonicalize(repo)

    on_exit(fn ->
      case Repo.get_by(Project, canonical_path: canonical) do
        %Project{id: id} -> Projects.Supervisor.stop_runtime(id)
        nil -> :ok
      end

      File.rm_rf(repo)
    end)

    %{repo: repo}
  end

  test "opens a git repository, records an event, and starts a runtime", %{repo: repo} do
    assert {:ok, project} = Projects.open_project(repo)
    assert {:ok, canonical} = Paths.canonicalize(repo)
    assert project.canonical_path == canonical
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

  test "opens a repository from a file inside it", %{repo: repo} do
    file = Path.join(repo, "README.md")
    File.write!(file, "# repo\n")

    assert {:ok, project} = Projects.open_project(file)
    assert {:ok, canonical} = Paths.canonicalize(repo)
    assert project.canonical_path == canonical

    on_exit(fn -> AgentDesk.Projects.Supervisor.stop_runtime(project.id) end)
  end

  test "rejects a missing path" do
    missing = Path.join(System.tmp_dir!(), "missing-repo-#{System.unique_integer([:positive])}")
    assert Projects.open_project(missing) == {:error, :not_found}
  end

  test "runtime startup failure returns a tagged error and leaves the project closed", %{
    repo: repo
  } do
    manager = AgentDesk.Projects.Supervisor.Manager
    assert :ok = Supervisor.terminate_child(Projects.Supervisor, manager)

    on_exit(fn ->
      case Supervisor.restart_child(Projects.Supervisor, manager) do
        {:ok, _pid} -> :ok
        {:ok, _pid, _info} -> :ok
        {:error, :running} -> :ok
      end
    end)

    assert {:error, {:runtime_start_failed, {:project_supervisor_unavailable, _reason}}} =
             Projects.open_project(repo)

    assert {:ok, canonical} = Paths.canonicalize(repo)
    project = Repo.get_by!(Project, canonical_path: canonical)
    refute project.open
    assert is_nil(project.last_opened_at)
    assert Runtime.fetch(project.id) == {:error, :not_started}
    assert Events.list_for_project(project.id) == []
  end

  test "restore_last_opened starts the runtime for the most recent project", %{repo: repo} do
    {:ok, project} = Projects.open_project(repo)
    :ok = AgentDesk.Projects.Supervisor.stop_runtime(project.id)

    assert {:ok, restored} = Projects.restore_last_opened()
    assert restored.id == project.id
    assert {:ok, pid} = Runtime.fetch(project.id)
    assert Process.alive?(pid)
  end

  test "keeps two project runtimes alive at the same time" do
    repo_a = GitRepo.tmp_repo!()
    repo_b = GitRepo.tmp_repo!()
    {:ok, a} = Projects.open_project(repo_a)
    {:ok, b} = Projects.open_project(repo_b)

    assert {:ok, pid_a} = Runtime.fetch(a.id)
    assert {:ok, pid_b} = Runtime.fetch(b.id)
    assert Process.alive?(pid_a)
    assert Process.alive?(pid_b)
    assert a.open
    assert b.open
    assert MapSet.new(Enum.map(Projects.list_open(), & &1.id)) == MapSet.new([a.id, b.id])
  after
    :ok
  end

  test "restore_on_boot restarts every open project and skips closed ones" do
    repo_a = GitRepo.tmp_repo!()
    repo_b = GitRepo.tmp_repo!()
    {:ok, a} = Projects.open_project(repo_a)
    {:ok, b} = Projects.open_project(repo_b)
    :ok = Projects.close_project(a)
    :ok = AgentDesk.Projects.Supervisor.stop_runtime(b.id)

    assert :ok = Projects.restore_on_boot()
    assert Runtime.fetch(a.id) == {:error, :not_started}
    assert {:ok, pid} = Runtime.fetch(b.id)
    assert Process.alive?(pid)
  end

  test "close_project stops the runtime and appends a closed event", %{repo: repo} do
    {:ok, project} = Projects.open_project(repo)
    assert :ok = Projects.close_project(project)
    assert Runtime.fetch(project.id) == {:error, :not_started}

    types = project.id |> Events.list_for_project() |> Enum.map(& &1.type)
    assert "project.closed" in types
  end

  test "forget_recent drops the project from recents without deleting the row", %{repo: repo} do
    {:ok, project} = Projects.open_project(repo)
    :ok = Projects.close_project(project)

    assert :ok = Projects.forget_recent(project)
    assert Projects.list_recent() == []
    assert {:ok, forgotten} = Projects.get_project(project.id)
    assert forgotten.last_opened_at == nil
    assert forgotten.open == false
  end

  test "reopen_project re-validates the stored path", %{repo: repo} do
    {:ok, project} = Projects.open_project(repo)
    :ok = AgentDesk.Projects.Supervisor.stop_runtime(project.id)

    assert {:ok, reopened} = Projects.reopen_project(project.id)
    assert reopened.id == project.id
    assert {:ok, _pid} = Runtime.fetch(project.id)

    File.rm_rf!(repo)
    assert Projects.reopen_project(project.id) == {:error, :not_found}
  end

  test "open_project starts the internal A2A hub", %{repo: repo} do
    {:ok, project} = Projects.open_project(repo)
    assert [{pid, _}] = Registry.lookup(AgentDesk.A2ASupervisorRegistry, project.id)
    assert Process.alive?(pid)
  end
end
