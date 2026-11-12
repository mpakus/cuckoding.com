defmodule Boss.AgentRolesTest do
  use Boss.DataCase, async: false
  alias Boss.Agents.{Detections, ModelDiscovery, Roles}

  setup do
    authorize_agents([:codex, :claude, :cursor])
    :ok
  end

  test "Analytic prefers an independent agent from the Implementer when available, and supports Claude" do
    roles = Map.new(Roles.list(), &{&1.kind, &1})
    assert {:ok, _} = Roles.assign(roles["analytic"].id, ["claude", "cursor"])
    assert Roles.analytic("cursor") == "claude"
    assert Roles.analytic("claude") == "cursor"

    assert {:ok, _} = Roles.assign(roles["analytic"].id, ["cursor"])
    assert Roles.analytic("cursor") == "cursor"

    assert {:ok, _} = Roles.assign(roles["implementer"].id, ["claude"])
    assert Roles.implementer() == "claude"
  end

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

  test "roles keep many agents, persist model and reasoning choices, and reject unauthorized or unsupported models" do
    roles = Map.new(Roles.list(), &{&1.kind, &1})
    reviewer = roles["reviewer"]
    implementer = roles["implementer"]

    assert {:ok, _} =
             Roles.assign(implementer.id, ["codex", "cursor"], %{
               "codex" => %{"model_id" => "gpt-6.1-sol", "reasoning_effort" => "high"},
               "cursor" => %{
                 "model_id" => "claude-sonnet-4-thinking",
                 "reasoning_effort" => "high"
               }
             })

    assert {:ok, _} =
             Roles.assign(reviewer.id, ["cursor", "claude"], %{
               "claude" => %{"model_id" => "claude-opus-4-6", "reasoning_effort" => "high"}
             })

    loaded = Map.new(Roles.list(), &{&1.kind, &1})
    assert loaded["implementer"].agent_ids == ["codex", "cursor"]
    assert loaded["reviewer"].agent_ids == ["claude", "cursor"]

    assert Roles.selection_for("implementer", "codex") == %{
             model_id: "gpt-6.1-sol",
             reasoning_effort: "high"
           }

    assert Roles.selection_for("reviewer", "claude") == %{
             model_id: "claude-opus-4-6",
             reasoning_effort: "high"
           }

    # Undetected / unauthorized agents are rejected
    assert {:error, :agent_not_authorized} = Roles.assign(reviewer.id, ["hermes"])

    Detections.mark_auth_status(:cursor, :stale)
    assert {:error, :agent_not_authorized} = Roles.assign(implementer.id, ["cursor"])
    # Active role resolution also skips stale/unauthorized agents
    assert Enum.map(Roles.agents_for("implementer"), & &1.id) == ["codex"]

    # Unsupported model IDs or efforts are rejected
    assert {:error, :model_not_supported} =
             Roles.assign(implementer.id, ["codex"], %{
               "codex" => %{"model_id" => "nonexistent-model"}
             })

    assert {:error, :invalid_reasoning_effort} =
             Roles.assign(implementer.id, ["codex"], %{
               "codex" => %{"model_id" => "gpt-6.1-sol", "reasoning_effort" => "impossible"}
             })
  end

  test "model discovery parses Codex, Cursor, Claude, and OpenCode models with pricing and reasoning" do
    codex_json =
      Jason.encode!(%{
        "models" => [
          %{
            "slug" => "gpt-6.1-sol",
            "display_name" => "GPT-6.1 Sol",
            "visibility" => "list",
            "context_window" => 500_000,
            "default_reasoning_level" => "high",
            "supported_reasoning_levels" => [%{"effort" => "medium"}, %{"effort" => "high"}]
          },
          %{"slug" => "gpt-reserve", "visibility" => "hide"}
        ]
      })

    assert {:ok, [m1]} = ModelDiscovery.parse_codex_models(codex_json)
    assert m1["id"] == "gpt-6.1-sol"
    assert m1["reasoning"] == true
    assert m1["reasoning_efforts"] == ["medium", "high"]
    assert m1["pricing"]["input"] == 2.0
    assert m1["pricing"]["output"] == 10.0

    cursor_text = """
    Available models
    claude-sonnet-4-thinking - Claude 4 Sonnet Thinking (current)
    gpt-4o - GPT-4o
    Tip: pass --model <id>
    """

    assert {:ok, [c1, c2]} = ModelDiscovery.parse_cursor_models(cursor_text)
    assert c1["id"] == "claude-sonnet-4-thinking"
    assert c1["name"] == "Claude 4 Sonnet Thinking"
    assert c1["reasoning"] == true
    assert c1["reasoning_efforts"] == []
    assert c1["pricing"]["input"] == 3.0
    assert c2["id"] == "gpt-4o"

    opencode_text = """
    opencode-go/gpt-6-luna
    {
      "id": "gpt-6-luna",
      "providerID": "opencode-go",
      "name": "GPT-6 Luna",
      "cost": {"input": 0.1, "output": 0.5, "cache": {"read": 0.01}},
      "limit": {"context": 272000},
      "capabilities": {"reasoning": true},
      "variants": {"low": {}, "high": {}}
    }
    """

    assert {:ok, [o1]} = ModelDiscovery.parse_opencode_models(opencode_text)
    assert o1["id"] == "opencode-go/gpt-6-luna"
    assert o1["pricing"]["input"] == 0.1
    assert o1["pricing"]["output"] == 0.5
    assert o1["reasoning_efforts"] == ["low", "high"]

    claude_list = ModelDiscovery.claude_models(["low", "high", "max"])

    assert Enum.any?(
             claude_list,
             &(&1["id"] == "claude-opus-4-6" and &1["pricing"]["input"] == 5.0)
           )
  end

  test "a catalog from a different CLI version is never reused" do
    saved = Detections.get_view(:codex)
    assert saved.models != []

    updated =
      saved
      |> Map.drop([:models])
      |> Map.put(:version, "2.0.0")
      |> Detections.save_agent()

    assert updated.version == "2.0.0"
    assert updated.models == []
    assert updated.models_checked_at == nil
  end

  test "a slow scan cannot overwrite a newer observation" do
    old = Detections.get_view(:codex)
    started_at = DateTime.add(old.checked_at, 1, :microsecond)
    newer = DateTime.add(started_at, 1, :microsecond)
    assert %{auth_status: :stale} = Detections.save_agent(%{old | auth_status: :stale}, newer)
    assert %{auth_status: :stale} = Detections.save_agent(old, started_at)
    assert %{models: []} = Detections.get_view(:codex)

    # A later-started probe still wins when the older one commits first.
    older = DateTime.add(newer, 1, :microsecond)
    later = DateTime.add(older, 1, :microsecond)
    assert %{auth_status: :stale} = Detections.save_agent(%{old | auth_status: :stale}, older)
    assert %{auth_status: :configured} = Detections.save_agent(old, later)
  end

  test "persisted catalog accepts qualified model IDs and deduplicates them" do
    id = "provider/model[1m]"

    assert %{models: [%{"id" => ^id, "name" => "First"}]} =
             Detections.save_models(:claude, [
               %{"id" => id, "name" => "First"},
               %{"id" => id, "name" => "Duplicate"},
               %{"id" => "invalid model"}
             ])

    {:ok, role} = Roles.create("Extended context")
    assert {:ok, _} = Roles.assign_member(role.id, "claude", %{"model_id" => id})
  end

  test "effort must come from the exact selected model" do
    {:ok, role} = Roles.create("Model testing")
    Detections.save_models(:cursor, [%{"id" => "auto", "reasoning_efforts" => []}])

    for model_id <- ["auto", "__default__"] do
      assert {:error, :invalid_reasoning_effort} =
               Roles.assign(role.id, ["cursor"], %{
                 "cursor" => %{"model_id" => model_id, "reasoning_effort" => "high"}
               })
    end
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

  defp authorize_agents(ids) do
    rows =
      Enum.map(ids, fn id ->
        models =
          case id do
            :codex ->
              [
                %{
                  "id" => "gpt-6.1-sol",
                  "name" => "GPT-6.1 Sol",
                  "reasoning" => true,
                  "reasoning_efforts" => ["medium", "high", "xhigh"],
                  "pricing" => %{"input" => 2.0, "output" => 10.0, "unit" => "1M tokens"}
                }
              ]

            :claude ->
              ModelDiscovery.claude_models()

            :cursor ->
              [
                %{
                  "id" => "claude-sonnet-4-thinking",
                  "name" => "Claude Sonnet Thinking",
                  "reasoning" => true,
                  "reasoning_efforts" => ["low", "medium", "high"],
                  "pricing" => %{"input" => 3.0, "output" => 15.0, "unit" => "1M tokens"}
                }
              ]
          end

        %{
          id: id,
          name: Atom.to_string(id),
          path: "/tools/#{id}",
          version: "1.0.0",
          probe_status: :ok,
          auth_status: :configured,
          capabilities: %{},
          errors: [],
          models: models
        }
      end)

    Detections.save_scan(rows)
  end
end
