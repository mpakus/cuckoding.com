defmodule AgentDesk.ContainersTest do
  use AgentDesk.DataCase

  alias AgentDesk.Agents
  alias AgentDesk.Containers
  alias AgentDesk.GitRepo
  alias AgentDesk.Isolation
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope
  alias AgentDesk.Worktrees

  @safe_compose """
  services:
    db:
      image: postgres:16
      ports:
        - "127.0.0.1:5432:5432"
  """

  @unsafe_compose """
  services:
    web:
      image: nginx
      ports:
        - "0.0.0.0:80:80"
  """

  setup do
    repo = GitRepo.tmp_repo!()
    %{repo: repo}
  end

  test "does nothing unless the session opts in", %{repo: repo} do
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)

    {:ok, session} =
      Providers.start_session(scope, %{provider: "fake", display_name: "Plain"})

    refute Containers.enabled?(session)
    refute File.exists?(Containers.record_path(session))
  end

  test "starts compose in the isolated worktree and records the project name", %{repo: repo} do
    GitRepo.add_file!(repo, "compose.yaml", @safe_compose)
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)

    {:ok, session} =
      Providers.start_session(scope, %{
        provider: "fake",
        display_name: "Boxed",
        settings: %{"tab_open" => true, "container" => true}
      })

    assert wait_until(fn -> File.exists?(Containers.record_path(session)) end)
    payload = Jason.decode!(File.read!(Containers.record_path(session)))
    assert payload["action"] == "up"
    assert payload["name"] == Isolation.compose_project(session)
    worktree = Worktrees.get_for_session(session.id)
    assert payload["directory"] == worktree.path

    leases = Manager.list_project(project.id)

    assert Enum.any?(
             leases,
             &(&1.resource_key == "compose:" <> Isolation.compose_project(session))
           )
  end

  test "rejects compose that publishes on all interfaces", %{repo: repo} do
    GitRepo.add_file!(repo, "compose.yaml", @unsafe_compose)
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)

    assert {:error, :non_loopback_publish} =
             Providers.start_session(scope, %{
               provider: "fake",
               display_name: "OpenNet",
               settings: %{"container" => true}
             })
  end

  test "refuses to run compose against the primary checkout", %{repo: repo} do
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)

    {:ok, session} =
      Agents.create_session(scope, %{
        provider: "fake",
        display_name: "Main",
        settings: %{"container" => true}
      })

    assert {:error, :primary_tree} = Containers.start(project, session)
  end
end
