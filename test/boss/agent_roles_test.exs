defmodule Boss.AgentRolesTest do
  use Boss.DataCase, async: false
  alias Boss.Agents.Roles

  test "roles keep many agents and agents keep many roles" do
    assert {:ok, _} = Roles.create("Developer")
    assert {:ok, _} = Roles.create("Reviewer")
    [developer, reviewer] = Roles.list()
    assert {:ok, _} = Roles.assign(developer.id, ["codex", "cursor"])
    assert {:ok, _} = Roles.assign(reviewer.id, ["cursor", "claude"])

    roles = Map.new(Roles.list(), &{&1.name, &1.agent_ids})
    assert roles["Developer"] == ["codex", "cursor"]
    assert roles["Reviewer"] == ["claude", "cursor"]

    assert {:ok, _} = Roles.assign(developer.id, ["codex"])
    roles = Map.new(Roles.list(), &{&1.name, &1.agent_ids})
    assert roles["Developer"] == ["codex"]
    assert roles["Reviewer"] == ["claude", "cursor"]
  end

  test "names can be created, renamed, and removed" do
    assert {:ok, role} = Roles.create("  Planner  ")
    assert role.name == "Planner"
    assert {:ok, renamed} = Roles.update(role.id, "Architect")
    assert renamed.name == "Architect"
    assert {:ok, _} = Roles.delete(role.id)
    assert Roles.list() == []
    assert {:error, :not_found} = Roles.update(role.id, "Architect")
  end

  test "blank, duplicate, and unknown agents are refused" do
    assert {:error, _} = Roles.create("   ")
    assert {:ok, _} = Roles.create("Reviewer")
    assert {:error, changeset} = Roles.create("Reviewer")
    assert Keyword.has_key?(changeset.errors, :name)
    [%{id: id}] = Roles.list()
    assert {:error, :unknown_agent} = Roles.assign(id, ["cursor", "editor"])
    assert Roles.list() == [%{id: id, name: "Reviewer", agent_ids: []}]
  end
end
