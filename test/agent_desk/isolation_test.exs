defmodule AgentDesk.IsolationTest do
  use AgentDesk.DataCase

  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.Isolation
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Scope
  alias AgentDesk.Worktrees

  test "writes database and compose templates outside the primary tree" do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)

    {:ok, session} =
      Providers.start_session(scope, %{provider: "fake", display_name: "Isolated"})

    dest = Isolation.dir(session)
    assert File.dir?(dest)
    refute String.starts_with?(dest, project.canonical_path)

    worktree = Worktrees.get_for_session(session.id)
    refute String.starts_with?(dest, worktree.path)

    env = File.read!(Path.join(dest, "env"))
    assert env =~ Isolation.test_database(session)
    assert env =~ Isolation.test_schema(session)
    assert env =~ Isolation.test_partition(session)
    assert env =~ Isolation.compose_project(session)
    assert env =~ "AGENTDESK_BIND=127.0.0.1"

    sql = File.read!(Path.join(dest, "postgres.database.sql"))
    assert sql =~ "CREATE DATABASE #{Isolation.test_database(session)}"
    assert File.read!(Path.join(dest, "postgres.schema.sql")) =~ Isolation.test_schema(session)
    assert File.read!(Path.join(dest, "elixir.test.exs")) =~ "MIX_TEST_PARTITION"

    assert File.read!(Path.join(dest, "compose.overlay.yaml")) =~
             Isolation.compose_project(session)

    profile = Isolation.profile(session)
    assert profile["database"] == Isolation.test_database(session)
    assert is_integer(profile["port"])
  end

  test "names stay unique across sessions" do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)

    {:ok, alice} = Agents.create_session(scope, %{provider: "fake", display_name: "Alice"})
    {:ok, bob} = Agents.create_session(scope, %{provider: "fake", display_name: "Bob"})

    assert Isolation.test_database(alice) != Isolation.test_database(bob)
    assert Isolation.test_schema(alice) != Isolation.test_schema(bob)
    assert Isolation.test_partition(alice) != Isolation.test_partition(bob)
    assert Isolation.compose_project(alice) != Isolation.compose_project(bob)
  end
end
