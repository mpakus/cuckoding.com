defmodule AgentDesk.ReviewsTest do
  use AgentDesk.DataCase

  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Projects.Project
  alias AgentDesk.Repo
  alias AgentDesk.Reviews
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

  test "publishing a handoff enqueues it without merging", %{
    project: project,
    alice: alice,
    alice_scope: alice_scope
  } do
    {:ok, worktree} = Worktrees.ensure_for_session(project, alice)
    File.write!(Path.join(worktree.path, "feat.txt"), "done\n")

    assert {:ok, result} = Handoffs.publish(alice_scope, %{summary: "Added feat"})
    [item] = Reviews.list_open(project)
    assert item.artifact_id == result.artifact.id
    assert item.status == "queued"
    refute File.exists?(Path.join(project.canonical_path, "feat.txt"))
  end

  test "accepting a handoff does not merge", %{
    project: project,
    alice: alice,
    alice_scope: alice_scope
  } do
    {:ok, worktree} = Worktrees.ensure_for_session(project, alice)
    File.write!(Path.join(worktree.path, "feat.txt"), "done\n")
    {:ok, result} = Handoffs.publish(alice_scope, %{summary: "Added feat"})

    assert {:ok, %{merged: false, status: "accepted"}} =
             Handoffs.accept(alice_scope, result.artifact.id)

    refute File.exists?(Path.join(project.canonical_path, "feat.txt"))
  end

  test "failed required checks block merge", %{
    project: project,
    alice: alice
  } do
    project =
      project
      |> Project.changeset(%{settings: %{"required_checks" => ["mix test"]}})
      |> Repo.update!()

    alice_scope = Scope.for_agent(project, alice)
    {:ok, worktree} = Worktrees.ensure_for_session(project, alice)
    File.write!(Path.join(worktree.path, "feat.txt"), "done\n")

    {:ok, result} =
      Handoffs.publish(alice_scope, %{
        summary: "Added feat",
        checks: [%{"name" => "mix test", "status" => "failed"}]
      })

    {:ok, _} = Handoffs.accept(alice_scope, result.artifact.id)
    [item] = Reviews.list_open(project)
    assert item.policy_status == "failed"
    assert {:error, :policy_failed} = Reviews.merge(project, item.id)
    refute File.exists?(Path.join(project.canonical_path, "feat.txt"))
  end

  test "accepted passing handoff merges into the primary branch", %{
    project: project,
    alice: alice,
    alice_scope: alice_scope
  } do
    {:ok, worktree} = Worktrees.ensure_for_session(project, alice)
    File.write!(Path.join(worktree.path, "feat.txt"), "done\n")
    {:ok, result} = Handoffs.publish(alice_scope, %{summary: "Added feat"})
    {:ok, _} = Handoffs.accept(alice_scope, result.artifact.id)
    [item] = Reviews.list_open(project)

    assert {:ok, merged} = Reviews.merge(project, item.id)
    assert merged.status == "merged"
    assert File.read!(Path.join(project.canonical_path, "feat.txt")) == "done\n"
    assert Reviews.list_open(project) == []
  end

  test "conflicting handoffs stay unmerged and do not dirty the primary tree", %{
    project: project,
    alice: alice,
    bob: bob,
    alice_scope: alice_scope,
    bob_scope: bob_scope
  } do
    {:ok, alice_wt} = Worktrees.ensure_for_session(project, alice)
    {:ok, bob_wt} = Worktrees.ensure_for_session(project, bob)

    File.write!(Path.join(alice_wt.path, "README.md"), "alice\n")
    {:ok, alice_h} = Handoffs.publish(alice_scope, %{summary: "alice"})
    {:ok, _} = Handoffs.accept(alice_scope, alice_h.artifact.id)
    [alice_item] = Reviews.list_open(project)
    assert {:ok, _} = Reviews.merge(project, alice_item.id)

    File.write!(Path.join(bob_wt.path, "README.md"), "bob\n")
    {:ok, bob_h} = Handoffs.publish(bob_scope, %{summary: "bob"})
    {:ok, _} = Handoffs.accept(bob_scope, bob_h.artifact.id)
    [bob_item] = Reviews.list_open(project)

    assert {:error, :conflict} = Reviews.merge(project, bob_item.id)
    refute AgentDesk.Git.dirty?(project.canonical_path)
    assert File.read!(Path.join(project.canonical_path, "README.md")) == "alice\n"
  end
end
