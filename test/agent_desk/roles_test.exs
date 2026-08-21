defmodule AgentDesk.RolesTest do
  use AgentDesk.DataCase

  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.MCP.Protocol
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Roles
  alias AgentDesk.Scope

  setup do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    on_exit(fn -> AgentDesk.Projects.Supervisor.stop_runtime(project.id) end)
    %{project: project, scope: Scope.for_project(project)}
  end

  test "seeds default roles without exposing prompts on the public map", %{project: project} do
    names = Enum.map(Roles.list(project), & &1.name)
    assert "implementer" in names
    assert "reviewer" in names
    assert "observer" in names

    observer = Enum.find(Roles.list(project), &(&1.name == "observer"))
    public = Roles.public_map(observer)
    refute Map.has_key?(public, "prompt")
    assert public["permission_profile"] == "observer"
  end

  test "attaches a role and interpolates the session prompt", %{scope: scope} do
    assert {:ok, session} =
             Providers.start_session(scope, %{
               provider: "fake",
               display_name: "Atlas",
               role: "observer"
             })

    assert session.role == "observer"
    assert session.settings["permission_profile"] == "observer"
    assert {:ok, prompt} = Roles.prompt_for(session)
    assert prompt =~ "Atlas"
    assert prompt =~ "observer"
    refute Roles.card_description(session, "Fake") =~ "You are"
  end

  test "rejects credentials in role names and keeps custom prompts off MCP", %{
    project: project,
    scope: scope
  } do
    assert {:error, changeset} = Roles.save(project, %{name: "api_key", description: "nope"})
    refute changeset.valid?

    assert {:ok, role} =
             Roles.save(project, %{
               name: "auditor",
               description: "Audits handoffs.",
               permission_profile: "restricted",
               prompt: "HIDDEN_PROMPT_TOKEN never publish"
             })

    {:ok, alice} = Agents.create_session(scope, %{provider: "fake", display_name: "Alice"})

    assert {:ok, %{"result" => %{"roles" => roles}}} =
             Protocol.handle(alice, %{
               "id" => 1,
               "method" => "tools/call",
               "params" => %{"name" => "hub_list_roles", "arguments" => %{}}
             })

    listed = Enum.find(roles, &(&1["id"] == role.id))
    assert listed["name"] == "auditor"
    refute inspect(roles) =~ "HIDDEN_PROMPT_TOKEN"
  end
end
