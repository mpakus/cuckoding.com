defmodule AgentDesk.MCP.ProtocolTest do
  use AgentDesk.DataCase

  alias AgentDesk.A2A
  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.MCP.Protocol
  alias AgentDesk.Projects
  alias AgentDesk.Scope
  alias AgentDesk.Security.Capability

  setup do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    project_scope = Scope.for_project(project)

    {:ok, alice} =
      Agents.create_session(project_scope, %{provider: "fake", display_name: "Alice"})

    {:ok, bob} = Agents.create_session(project_scope, %{provider: "fake", display_name: "Bob"})
    {:ok, token, alice} = Capability.issue(alice)

    %{
      alice: alice,
      bob: bob,
      token: token,
      project: project,
      alice_scope: Scope.for_agent(project, alice),
      bob_scope: Scope.for_agent(project, bob)
    }
  end

  test "initialize and tools/list expose the same hub surface", %{alice: alice} do
    assert {:ok, %{"result" => result}} =
             Protocol.handle(alice, %{"id" => 1, "method" => "initialize", "params" => %{}})

    assert result["serverInfo"]["name"] == "agentdesk-hub"

    assert {:ok, %{"result" => %{"tools" => tools}}} =
             Protocol.handle(alice, %{"id" => 2, "method" => "tools/list", "params" => %{}})

    names = Enum.map(tools, & &1["name"])
    assert "hub_register" in names
    assert "hub_claim_resources" in names
    assert "hub_send_message" in names
    assert "hub_list_agents" in names
    assert "project_search" in names
    assert "memory_remember" in names
    assert "memory_recall" in names
    assert "memory_forget" in names
    assert "hub_list_merge_queue" in names
    assert "hub_reject_handoff" in names
    assert "hub_list_task_graph" in names
    assert "hub_run_workflow" in names
    assert "hub_split_work" in names
    assert "hub_crew_status" in names
    assert "hub_list_roles" in names
    assert "hub_isolation" in names
  end

  test "capability tokens authenticate and reject unknown secrets", %{token: token, alice: alice} do
    assert {:ok, session} = Capability.authenticate(token)
    assert session.id == alice.id
    assert {:error, :unauthorized} = Capability.authenticate("nope")
  end

  test "hub_register and list_agents hide credentials", %{
    alice: alice,
    alice_scope: alice_scope,
    bob_scope: bob_scope
  } do
    assert {:ok, _} =
             Protocol.handle(alice, %{
               "id" => 3,
               "method" => "tools/call",
               "params" => %{
                 "name" => "hub_register",
                 "arguments" => %{
                   "name" => "Alice",
                   "description" => "dev",
                   "skills" => [%{"id" => "elixir"}]
                 }
               }
             })

    {:ok, _} =
      A2A.register_card(bob_scope, %{
        name: "Bob",
        description: "review",
        skills: [%{"id" => "review"}]
      })

    assert {:ok, %{"result" => %{"agents" => agents}}} =
             Protocol.handle(alice, %{
               "id" => 4,
               "method" => "tools/call",
               "params" => %{"name" => "hub_list_agents", "arguments" => %{}}
             })

    refute inspect(agents) =~ "password"
    names = Enum.map(agents, &(&1[:name] || &1["name"] || &1.name))
    assert "Alice" in names
    _ = alice_scope
  end

  test "hub_isolation returns session names without the worktree", %{
    alice: alice,
    project: project
  } do
    dest = AgentDesk.Isolation.write_templates!(alice)

    assert {:ok, %{"result" => profile}} =
             Protocol.handle(alice, %{
               "id" => 5,
               "method" => "tools/call",
               "params" => %{"name" => "hub_isolation", "arguments" => %{}}
             })

    assert profile["database"] == AgentDesk.Isolation.test_database(alice)
    assert profile["schema"] == AgentDesk.Isolation.test_schema(alice)
    assert profile["dir"] == dest
    refute String.starts_with?(profile["dir"], project.canonical_path)
  end

  test "hub_split_work creates specialist tasks for matching roles", %{
    alice: alice,
    bob: bob,
    alice_scope: alice_scope
  } do
    {:ok, _} = Agents.update_session(alice, %{role: "lead"})
    {:ok, _} = Agents.update_session(bob, %{role: "backend"})

    assert {:ok, %{"result" => result}} =
             Protocol.handle(alice, %{
               "id" => 6,
               "method" => "tools/call",
               "params" => %{
                 "name" => "hub_split_work",
                 "arguments" => %{
                   "goal" => "Add login API",
                   "lanes" => [
                     %{
                       "key" => "backend",
                       "role" => "backend",
                       "title" => "Login API",
                       "recipient_agent_id" => bob.id
                     }
                   ]
                 }
               }
             })

    assert result["lead_agent_id"] == alice.id
    assert [%{"role" => "backend", "agent_id" => bob_id}] = result["lanes"]
    assert bob_id == bob.id
    tasks = A2A.list_tasks(alice_scope)
    assert Enum.any?(tasks, &(&1.title =~ "Login API"))
  end
end
