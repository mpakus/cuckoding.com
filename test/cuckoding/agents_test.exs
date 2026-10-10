defmodule Cuckoding.AgentsTest do
  use Cuckoding.DataCase
  alias Cuckoding.{AgentConnection, Agents, Command, Foundation, Storage, Team}

  test "named profiles isolate version, catalog, selection, cancellation and signout" do
    first = add("First", "codex")
    second = add("Second", "codex")
    connect(first.id, "first-model", "chatgpt")
    connect(second.id, "second-model", "chatgpt")
    save_models(first.id, "first-model")
    save_models(second.id, "second-model")
    assert Foundation.workspace().codex == %{}
    assert Foundation.saved_agent_models() == nil
    assert Foundation.saved_agent_models(first.id).payload["model_ids"] == ["first-model"]
    assert Foundation.saved_agent_models(second.id).payload["model_ids"] == ["second-model"]
    assert Storage.codex_profile!(first.id) != Storage.codex_profile!(second.id)
    assert_raise RuntimeError, fn -> Storage.codex_profile!("../codex") end
    before = Agents.get(first.id)

    {:ok, command} =
      Foundation.authorize_codex(Ecto.UUID.generate(), revision(), :logout, true, second.id)

    assert Agents.get(second.id).connection["models"] == []
    assert Agents.get(first.id) == before
    {:ok, claim} = Foundation.claim()
    Foundation.cancel_probe(command.id)

    Foundation.finish(claim, %{
      "status" => "checked",
      "authorization" => "not_connected",
      "catalog_status" => "not_requested"
    })

    assert Repo.get!(Command, command.id).state == "cancelled"
    assert Agents.get(first.id) == before
    assert Foundation.saved_agent_models(second.id)
  end

  test "creation is idempotent and refuses stale intent, invalid names and foreign model receipts" do
    key = Ecto.UUID.generate()
    {:ok, pending} = Agents.add_and_probe(key, 0, "Planner", "cursor", "/bin/sh")
    assert {:ok, ^pending} = Agents.add_and_probe(key, 0, "Planner", "cursor", "/bin/sh")

    assert {:error, :key_conflict} =
             Agents.add_and_probe(key, 0, "Different", "cursor", "/bin/sh")

    assert Repo.aggregate(AgentConnection, :count) == 1
    Foundation.cancel_probe(key)

    assert {:error, _} =
             Agents.add_and_probe(Ecto.UUID.generate(), 999, "Stale", "codex", "/bin/sh")

    assert {:error, _} =
             Agents.add_and_probe(Ecto.UUID.generate(), 0, "bad\nname", "codex", "/bin/sh")

    first = add("A", "codex")
    second = add("B", "codex")
    connect(first.id, "same-id", "chatgpt")
    connect(second.id, "same-id", "chatgpt")

    assert {:ok, %{state: "rejected"}} =
             Foundation.save_agent_models(
               Ecto.UUID.generate(),
               revision(),
               Agents.get(first.id).connection["command_id"],
               ["same-id"],
               second.id
             )

    assert Foundation.saved_agent_models(second.id) == nil
    role = put_in(Team.editable(Team.current()), [Access.at(0), "agent"], Ecto.UUID.generate())
    assert {:error, "model_refresh_required"} = Team.save(Ecto.UUID.generate(), 1, role)
  end

  test "mixed roles use their own saved catalogs; no cross-agent model or diagnostic fallback" do
    codex = add("Coder", "codex")
    cursor = add("Planner", "cursor")
    connect(codex.id, "gpt-fixture", "chatgpt")
    connect(cursor.id, "grok-fixture", "cursor")
    save_models(codex.id, "gpt-fixture")
    assert Team.catalog(cursor.id).selectable_models == []
    save_models(cursor.id, "grok-fixture")

    roles =
      Team.editable(Team.current())
      |> List.update_at(0, &Map.merge(&1, %{"agent" => cursor.id, "model_id" => "grok-fixture"}))
      |> List.update_at(1, &Map.merge(&1, %{"agent" => codex.id, "model_id" => "gpt-fixture"}))

    assert {:ok, team} = Team.save(Ecto.UUID.generate(), 1, roles)
    assert Team.binding_status(hd(team.definition["roles"]), Team.catalog()) == :untested
    wrong = put_in(roles, [Access.at(0), "model_id"], "gpt-fixture")
    assert {:error, "model_refresh_required"} = Team.save(Ecto.UUID.generate(), team.id, wrong)

    assert {:error, _} =
             Foundation.check_model(
               Ecto.UUID.generate(),
               revision(),
               "grok-fixture",
               true,
               cursor.id
             )

    refute Foundation.model_check_current?(%{"agent_id" => cursor.id})

    before = Agents.get(cursor.id)

    {:ok, _} =
      Foundation.check_model(Ecto.UUID.generate(), revision(), "gpt-fixture", true, codex.id)

    {:ok, claim} = Foundation.claim()
    assert Foundation.agent_id(claim.payload) == codex.id
    Foundation.finish(claim, %{"status" => "model_unavailable"})
    assert Agents.get(cursor.id) == before
    refute Foundation.pending?()
  end

  test "planning freezes the selected Codex connection and Cursor never falls back to Codex" do
    codex = add("Planner", "codex")
    connect(codex.id, "test-model", "chatgpt")
    save_models(codex.id, "test-model")

    roles =
      Team.editable(Team.current())
      |> List.update_at(0, &Map.merge(&1, %{"agent" => codex.id, "model_id" => "test-model"}))

    {:ok, _} = Team.save(Ecto.UUID.generate(), 1, roles)
    arena = Cuckoding.DataCase.arena_fixture()
    {:ok, board} = Cuckoding.Tabulae.create(Ecto.UUID.generate(), arena.id, "Named planner")
    setup = Cuckoding.Planning.setup(board)
    assert setup.payload["agent_id"] == codex.id
    assert setup.payload["connection_command_id"] == Agents.get(codex.id).connection["command_id"]

    {:ok, _} =
      Cuckoding.Planning.request(
        Ecto.UUID.generate(),
        arena.id,
        board.id,
        "Plan",
        setup.token,
        true
      )

    {:ok, claim} = Foundation.claim()

    assert {:ok, %{state: "completed"}} =
             Foundation.finish(claim, Cuckoding.PlanningFixtures.planning_receipt(claim.id))

    cursor = add("Other planner", "cursor")
    connect(cursor.id, "grok-fixture", "cursor")
    save_models(cursor.id, "grok-fixture")

    next =
      Team.editable(Team.current())
      |> List.update_at(0, &Map.merge(&1, %{"agent" => cursor.id, "model_id" => "grok-fixture"}))

    {:ok, _} = Team.save(Ecto.UUID.generate(), Team.current().id, next)
    other_arena = Cuckoding.DataCase.arena_fixture()

    {:ok, other} =
      Cuckoding.Tabulae.create(Ecto.UUID.generate(), other_arena.id, "Cursor planner")

    assert Cuckoding.Planning.setup(other).payload == nil
    assert Cuckoding.Planning.setup(board).payload["agent_id"] == codex.id
  end

  test "expired setup cannot publish success or be replayed after a sleep gap" do
    {:ok, _} = Agents.add_and_probe(Ecto.UUID.generate(), 0, "Cursor", "cursor", "/bin/sh")
    {:ok, claim} = Foundation.claim(1000)

    assert {:error, :lost_claim} =
             Foundation.finish(claim, %{"status" => "supported", "version" => "fixture"})

    assert {:ok, %{state: "failed", result: "interrupted"}} = Foundation.claim(11_001)
    assert {:ok, nil} = Foundation.claim(11_002)
    assert Agents.get(claim.payload["agent_id"]).codex == %{}
  end

  defp revision, do: Foundation.workspace().revision

  defp add(name, kind) do
    {:ok, command} = Agents.add_and_probe(Ecto.UUID.generate(), revision(), name, kind, "/bin/sh")
    {:ok, claim} = Foundation.claim()
    {:ok, _} = Foundation.finish(claim, %{"status" => "supported", "version" => "fixture"})
    Agents.get(command.payload["agent_id"])
  end

  defp connect(id, model, auth) do
    {:ok, _} = Foundation.inspect_codex(Ecto.UUID.generate(), revision(), true, id)
    {:ok, claim} = Foundation.claim()

    row = %{
      "id" => model,
      "model" => model,
      "name" => model,
      "default" => true,
      "hidden" => false
    }

    row =
      if auth == "chatgpt",
        do:
          Map.merge(row, %{
            "efforts" => ["low"],
            "default_effort" => "low",
            "input_modalities" => ["text"]
          }),
        else: row

    Foundation.finish(claim, %{
      "status" => "checked",
      "authorization" => auth,
      "catalog_status" => "fresh",
      "models" => [row]
    })
  end

  defp save_models(id, model) do
    {:ok, %{state: "completed"}} =
      Foundation.save_agent_models(
        Ecto.UUID.generate(),
        revision(),
        Agents.get(id).connection["command_id"],
        [model],
        id
      )
  end
end
