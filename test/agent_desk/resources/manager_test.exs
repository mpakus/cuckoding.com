defmodule AgentDesk.Resources.ManagerTest do
  use AgentDesk.DataCase

  alias AgentDesk.Agents
  alias AgentDesk.Clock
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Repo
  alias AgentDesk.Resources.Lease
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope

  setup do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, alice} = Agents.create_session(scope, %{provider: "fake", display_name: "Alice"})
    {:ok, bob} = Agents.create_session(scope, %{provider: "fake", display_name: "Bob"})

    %{
      project: project,
      alice: Scope.for_agent(project, alice),
      bob: Scope.for_agent(project, bob)
    }
  end

  test "exclusive claims conflict deterministically", %{alice: alice, bob: bob} do
    resource = [%{"type" => "file", "key" => "lib/app.ex", "mode" => "exclusive"}]
    assert {:ok, _} = Manager.claim(alice, resource, reason: "edit")

    assert {:error, {:conflict, [%{requested_key: "lib/app.ex"}]}} =
             Manager.claim(bob, resource, reason: "edit")
  end

  test "directory lease blocks a child file claim", %{alice: alice, bob: bob} do
    assert {:ok, _} =
             Manager.claim(alice, [%{"type" => "file", "key" => "lib", "mode" => "exclusive"}],
               reason: "dir"
             )

    assert {:error, {:conflict, _}} =
             Manager.claim(
               bob,
               [%{"type" => "file", "key" => "lib/app.ex", "mode" => "exclusive"}],
               reason: "file"
             )
  end

  test "shared leases coexist until an exclusive claim", %{alice: alice, bob: bob} do
    shared = [%{"type" => "database", "key" => "app_test", "mode" => "shared"}]
    assert {:ok, _} = Manager.claim(alice, shared, reason: "read")
    assert {:ok, _} = Manager.claim(bob, shared, reason: "read")

    assert {:error, {:conflict, _}} =
             Manager.claim(
               alice,
               [%{"type" => "database", "key" => "app_test", "mode" => "exclusive"}],
               reason: "migrate"
             )
  end

  test "renew cannot resurrect an expired lease", %{alice: alice} do
    assert {:ok, [lease]} =
             Manager.claim(alice, [%{"type" => "port", "key" => "4001", "mode" => "exclusive"}],
               reason: "dev",
               ttl_seconds: 1
             )

    past = DateTime.add(Clock.utc_now(), -10, :second)

    lease
    |> Ecto.Changeset.change(%{expires_at: past})
    |> Repo.update!()

    Manager.expire_due(alice.project.id)
    assert {:error, :not_renewable} = Manager.renew(alice, [lease.id])
  end

  test "killing a session expires its leases", %{alice: alice} do
    assert {:ok, [_lease]} =
             Manager.claim(
               alice,
               [%{"type" => "custom", "key" => "compose", "mode" => "exclusive"}],
               reason: "docker"
             )

    Manager.expire_session(alice.agent_session.id)
    assert Manager.list_owned(alice.agent_session.id) == []
    assert Repo.get_by(Lease, agent_session_id: alice.agent_session.id).status == "expired"
  end
end
