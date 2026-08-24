defmodule AgentDesk.WorktreesTest do
  use AgentDesk.DataCase

  alias AgentDesk.Agents
  alias AgentDesk.Git
  alias AgentDesk.GitRepo
  alias AgentDesk.Isolation
  alias AgentDesk.Projects
  alias AgentDesk.Scope
  alias AgentDesk.Worktrees
  alias AgentDesk.Worktrees.Handoffs

  setup do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, alice} = Agents.create_session(scope, %{provider: "fake", display_name: "Alice"})
    {:ok, bob} = Agents.create_session(scope, %{provider: "fake", display_name: "Bob"})

    %{
      repo: repo,
      project: project,
      alice: alice,
      bob: bob,
      alice_scope: Scope.for_agent(project, alice),
      bob_scope: Scope.for_agent(project, bob)
    }
  end

  test "open_project records the default branch", %{project: project} do
    assert project.default_branch in ["main", "master"]
  end

  test "each session gets an isolated worktree and both edits survive", %{
    project: project,
    alice: alice,
    bob: bob
  } do
    assert {:ok, alice_wt} = Worktrees.ensure_for_session(project, alice)
    assert {:ok, bob_wt} = Worktrees.ensure_for_session(project, bob)
    assert alice_wt.path != bob_wt.path
    assert alice_wt.path != project.canonical_path

    File.write!(Path.join(alice_wt.path, "alice.txt"), "a\n")
    File.write!(Path.join(bob_wt.path, "bob.txt"), "b\n")

    assert File.exists?(Path.join(alice_wt.path, "alice.txt"))
    refute File.exists?(Path.join(bob_wt.path, "alice.txt"))
    assert File.exists?(Path.join(bob_wt.path, "bob.txt"))
    refute File.exists?(Path.join(project.canonical_path, "alice.txt"))
  end

  test "handoff includes commit, summary, files, and warnings", %{
    project: project,
    alice: alice,
    alice_scope: alice_scope
  } do
    {:ok, worktree} = Worktrees.ensure_for_session(project, alice)
    File.write!(Path.join(worktree.path, "feat.txt"), "done\n")

    assert {:ok, result} =
             Handoffs.publish(alice_scope, %{
               summary: "Added feat",
               warnings: ["needs review"]
             })

    assert result.artifact.kind == "handoff"
    assert result.commit
    assert "feat.txt" in result.changed_files
  end

  test "cherry-pick conflicts are visible and not auto-resolved", %{
    project: project,
    alice: alice,
    bob: bob
  } do
    {:ok, alice_wt} = Worktrees.ensure_for_session(project, alice)
    {:ok, bob_wt} = Worktrees.ensure_for_session(project, bob)

    File.write!(Path.join(alice_wt.path, "README.md"), "alice\n")
    {:ok, _} = Worktrees.commit(alice_wt, "alice edit")
    alice_wt = Worktrees.get_for_session(alice.id)

    File.write!(Path.join(bob_wt.path, "README.md"), "bob\n")
    {:ok, _} = Worktrees.commit(bob_wt, "bob edit")

    assert {:error, :conflict} = Git.prepare_cherry_pick(bob_wt.path, alice_wt.head_commit)
    assert Git.conflicted?(bob_wt.path)
    assert File.read!(Path.join(bob_wt.path, "README.md")) =~ "<<<<"
  end

  test "cleanup refuses dirty worktrees and restart keeps them", %{
    project: project,
    alice: alice
  } do
    {:ok, worktree} = Worktrees.ensure_for_session(project, alice)
    File.write!(Path.join(worktree.path, "dirty.txt"), "x\n")
    assert {:error, :dirty} = Worktrees.cleanup(project, worktree)

    AgentDesk.Projects.Supervisor.stop_runtime(project.id)
    {:ok, _pid} = AgentDesk.Projects.Supervisor.start_runtime(project)
    assert File.exists?(Path.join(worktree.path, "dirty.txt"))
    assert Worktrees.get_for_session(alice.id).path == worktree.path
  end

  test "isolation names and ports are unique per session", %{
    alice: alice,
    bob: bob,
    alice_scope: alice_scope,
    bob_scope: bob_scope
  } do
    assert Isolation.test_database(alice) != Isolation.test_database(bob)
    assert Isolation.compose_project(alice) != Isolation.compose_project(bob)
    assert {:ok, port_a} = Isolation.allocate_port(alice_scope)
    assert {:ok, port_b} = Isolation.allocate_port(bob_scope)
    assert port_a != port_b
  end

  test "explicit shared sessions skip a dedicated worktree", %{project: project} do
    scope = Scope.for_project(project)

    {:ok, shared} =
      Agents.create_session(scope, %{
        provider: "fake",
        display_name: "Shared",
        settings: %{"shared" => true}
      })

    assert {:ok, nil} = Worktrees.ensure_for_session(project, shared)
    assert Worktrees.working_copy_path(project, shared) == project.canonical_path
    assert is_nil(Worktrees.get_for_session(shared.id))
  end
end
