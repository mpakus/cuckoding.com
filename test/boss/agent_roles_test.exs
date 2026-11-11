defmodule Boss.AgentRolesTest do
  use Boss.DataCase, async: false
  alias Boss.Agents.Roles

  test "the sole Implementer agent is used for new work" do
    role = Enum.find(Roles.list(), &(&1.kind == "implementer"))
    assert {:ok, _} = Roles.assign(role.id, ["cursor"])
    assert Roles.implementer() == "cursor"
  end

  test "standard roles are present and keep their jobs" do
    roles = Map.new(Roles.list(), &{&1.kind, &1})
    assert roles["reviewer"].name == "Reviewer"
    assert roles["reviewer"].purpose =~ "Reviews specs and code"
    assert roles["implementer"].purpose =~ "Writes code and tests"
    assert roles["analytic"].purpose =~ "helps the Reviewer"
    assert {:error, :standard} = Roles.delete(roles["reviewer"].id)
    assert {:error, :standard} = Roles.update(roles["analytic"].id, "Analyst")
    assert MapSet.new(Enum.map(Roles.list(), & &1.kind)) |> MapSet.member?("analytic")
  end

  test "roles keep many agents and agents keep many roles" do
    roles = Map.new(Roles.list(), &{&1.kind, &1})
    reviewer = roles["reviewer"]
    implementer = roles["implementer"]
    assert {:ok, _} = Roles.assign(implementer.id, ["codex", "cursor"])
    assert {:ok, _} = Roles.assign(reviewer.id, ["cursor", "claude"])

    roles = Map.new(Roles.list(), &{&1.kind, &1.agent_ids})
    assert roles["implementer"] == ["codex", "cursor"]
    assert roles["reviewer"] == ["claude", "cursor"]

    assert {:ok, _} = Roles.assign(implementer.id, ["codex"])
    roles = Map.new(Roles.list(), &{&1.kind, &1.agent_ids})
    assert roles["implementer"] == ["codex"]
    assert roles["reviewer"] == ["claude", "cursor"]
  end

  test "custom names can be created, renamed, and removed" do
    assert {:ok, role} = Roles.create("  Planner  ")
    assert role.name == "Planner"
    assert {:ok, renamed} = Roles.update(role.id, "Architect")
    assert renamed.name == "Architect"
    assert {:ok, _} = Roles.delete(role.id)
    refute Enum.any?(Roles.list(), &(&1.name == "Architect"))
    assert {:error, :not_found} = Roles.update(role.id, "Architect")
  end

  test "blank, duplicate, and unknown agents are refused" do
    assert {:error, _} = Roles.create("   ")
    assert {:error, changeset} = Roles.create("Reviewer")
    assert Keyword.has_key?(changeset.errors, :name)
    reviewer = Enum.find(Roles.list(), &(&1.kind == "reviewer"))
    assert {:error, :unknown_agent} = Roles.assign(reviewer.id, ["cursor", "editor"])
    assert reviewer.agent_ids == []
  end
end
