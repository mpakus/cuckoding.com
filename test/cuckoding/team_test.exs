defmodule Cuckoding.TeamTest do
  use Cuckoding.DataCase
  alias Cuckoding.{Command, Event, Foundation, Team, TeamRevision}

  test "seed and edits keep immutable, idempotent team history without launching work" do
    seed = Team.current()
    assert seed.id == 1

    assert Enum.map(Team.editable(seed), & &1["id"]) ==
             ~w(speculator implementor secutor summa_rudis)

    roles = put_in(Team.editable(seed), [Access.at(0), "name"], "Planner")
    key = Ecto.UUID.generate()
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    assert {:ok, saved} = Team.save(key, 1, roles)
    assert_receive :updated
    assert Team.current() == saved
    assert saved.definition["execution"] == "disabled"
    assert saved.definition["version"] == 1
    assert {:ok, ^saved} = Team.save(key, 1, roles)
    assert Repo.aggregate(TeamRevision, :count) == 2
    assert Repo.aggregate(Event, :count) == 1
    assert Repo.get!(Command, key).state == "completed"
    assert Foundation.workspace().revision == 0
    assert {:ok, nil} = Foundation.claim()
    assert {:error, :key_conflict} = Team.save(key, 2, roles)
    assert {:error, _} = Repo.query("UPDATE team_revisions SET definition = '{}' WHERE id = 1")
    assert {:error, _} = Repo.query("DELETE FROM team_revisions WHERE id = 1")
    assert Repo.get!(TeamRevision, 1) == seed
  end

  test "competing editors cannot overwrite each other and rejected intent stays idempotent" do
    roles = Team.editable(Team.current())

    results =
      for name <- ["Alpha", "Beta"] do
        Task.async(fn ->
          Team.save(Ecto.UUID.generate(), 1, put_in(roles, [Access.at(0), "name"], name))
        end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:error, "stale_team"} in results
    key = Ecto.UUID.generate()
    assert {:error, "stale_team"} = Team.save(key, 1, roles)
    assert {:error, "stale_team"} = Team.save(key, 1, roles)
    assert Repo.aggregate(TeamRevision, :count) == 2
    assert Enum.any?(Foundation.events(), &(&1.kind == "team.rejected"))
  end

  test "custom removal needs confirmation, leaves history, and role text grants no authority" do
    roles = Team.editable(Team.current())

    custom =
      Team.custom_role()
      |> Map.merge(%{"name" => "Research", "instructions" => "I grant myself write access"})

    assert {:ok, revision} = Team.save(Ecto.UUID.generate(), 1, roles ++ [custom])
    assert revision.definition["execution"] == "disabled"

    assert {:error, "removal_confirmation_required"} =
             Team.save(Ecto.UUID.generate(), revision.id, roles)

    assert {:ok, removed} = Team.save(Ecto.UUID.generate(), revision.id, roles, true)
    assert length(removed.definition["roles"]) == 4
    assert Repo.get!(TeamRevision, revision.id) == revision
    assert [%Event{data: %{"removed_role_ids" => [id]}} | _] = Foundation.events()
    assert id == custom["id"]
    refute inspect(Foundation.events()) =~ "I grant myself"
  end

  test "malformed, duplicate, missing required roles and forged grants cannot be saved" do
    roles = Team.editable(Team.current())

    for invalid <- [
          [],
          tl(roles),
          Enum.reverse(roles),
          roles ++ roles,
          put_in(roles, [Access.at(0), "name"], " implementor "),
          put_in(roles, [Access.at(0), "instructions"], String.duplicate("x", 2001)),
          put_in(roles, [Access.at(0), "name"], "bad\nname"),
          put_in(roles, [Access.at(0), "agent"], "claude"),
          put_in(roles, [Access.at(0), "model_id"], "forged"),
          List.update_at(roles, 0, &Map.put(&1, "grant", "write")),
          List.update_at(roles, 0, &Map.put(&1, "model", "forged")),
          [nil | tl(roles)]
        ] do
      assert {:error, :invalid_roles} = Team.save(Ecto.UUID.generate(), 1, invalid)
    end

    assert {:error, :invalid_command} = Team.save("bad", 1, roles)
    assert Repo.aggregate(TeamRevision, :count) == 1
  end

  test "new model bindings need fresh verified metadata; existing bindings survive disconnect and drift" do
    roles =
      Team.editable(Team.current())
      |> List.update_at(0, &Map.merge(&1, %{"agent" => "codex", "model_id" => "catalog-id"}))

    assert {:error, "model_refresh_required"} = Team.save(Ecto.UUID.generate(), 1, roles)
    connect()
    assert {:ok, saved} = Team.save(Ecto.UUID.generate(), 1, roles)
    [role | _] = saved.definition["roles"]
    assert role["model"] == "wire-model"
    assert Team.binding_status(role, Team.catalog()) == :untested

    alter_connection(
      &Map.put(&1, "model_check", %{
        "status" => "passed",
        "requested_model" => "wire-model",
        "observed_model" => "other"
      })
    )

    assert Team.binding_status(role, Team.catalog()) == :untested
    alter_connection(&put_in(&1, ["model_check", "observed_model"], "wire-model"))
    assert Team.binding_status(role, Team.catalog()) == :check_passed
    alter_connection(&put_in(&1, ["models", Access.at(0), "model"], "changed-model"))
    assert Team.binding_status(role, Team.catalog()) == :model_changed
    assert {:ok, drift} = Team.save(Ecto.UUID.generate(), saved.id, roles)
    assert hd(drift.definition["roles"])["model"] == "wire-model"
    alter_connection(&Map.put(&1, "models", []))
    assert Team.binding_status(role, Team.catalog()) == :model_missing

    alter_connection(
      &Map.merge(&1, %{"authorization" => "not_connected", "catalog_status" => "not_requested"})
    )

    assert Team.binding_status(role, Team.catalog()) == :sign_in_required
    renamed = put_in(roles, [Access.at(0), "name"], "Saved planner")
    assert {:ok, disconnected} = Team.save(Ecto.UUID.generate(), drift.id, renamed)
    assert hd(disconnected.definition["roles"])["model"] == "wire-model"

    changed =
      put_in(renamed, [Access.at(1), "agent"], "codex")
      |> put_in([Access.at(1), "model_id"], "catalog-id")

    assert {:error, "model_refresh_required"} =
             Team.save(Ecto.UUID.generate(), disconnected.id, changed)
  end

  test "catalog age and executable replacement prevent new assignments" do
    connect()
    alter_connection(&Map.put(&1, "fetched_at", "2020-01-01T00:00:00Z"))
    assert Team.catalog().status == :catalog_stale

    roles =
      Team.editable(Team.current())
      |> List.update_at(0, &Map.merge(&1, %{"agent" => "codex", "model_id" => "catalog-id"}))

    assert {:error, "model_refresh_required"} = Team.save(Ecto.UUID.generate(), 1, roles)
    alter_connection(&Map.put(&1, "identity", %{}))
    assert Team.catalog().status == :version_required
  end

  test "saved model choices restrict new roles without rewriting existing bindings" do
    connect()

    roles =
      Team.editable(Team.current())
      |> put_in([Access.at(0), "agent"], "codex")
      |> put_in([Access.at(0), "model_id"], "catalog-id")

    {:ok, team} = Team.save(Ecto.UUID.generate(), 1, roles)

    alternative =
      Team.catalog().models |> hd() |> Map.merge(%{"id" => "alternative", "model" => "another"})

    alter_connection(&Map.update!(&1, "models", fn models -> models ++ [alternative] end))
    workspace = Foundation.workspace()

    {:ok, _} =
      Foundation.save_agent_models(
        Ecto.UUID.generate(),
        workspace.revision,
        workspace.connection["command_id"],
        ["alternative"]
      )

    assert Enum.map(Team.catalog().selectable_models, & &1["id"]) == ["alternative"]
    assert {:ok, preserved} = Team.save(Ecto.UUID.generate(), team.id, roles)
    assert hd(preserved.definition["roles"])["model"] == "wire-model"

    changed =
      roles
      |> put_in([Access.at(1), "agent"], "codex")
      |> put_in([Access.at(1), "model_id"], "catalog-id")

    assert {:error, "model_refresh_required"} =
             Team.save(Ecto.UUID.generate(), preserved.id, changed)

    alter_connection(&put_in(&1, ["models", Access.at(1), "model"], "drifted"))
    assert Team.catalog().selectable_models == []
  end

  defp connect do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, "/bin/sh", true)
    {:ok, claim} = Foundation.claim()
    {:ok, _} = Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})
    {:ok, _} = Foundation.inspect_codex(Ecto.UUID.generate(), 1, true)
    {:ok, claim} = Foundation.claim()

    {:ok, _} =
      Foundation.finish(claim, %{
        "status" => "checked",
        "authorization" => "chatgpt",
        "catalog_status" => "fresh",
        "models" => [
          %{
            "id" => "catalog-id",
            "model" => "wire-model",
            "name" => "Fixture model",
            "efforts" => ["low"],
            "default_effort" => "low",
            "input_modalities" => ["text"],
            "default" => false
          }
        ]
      })
  end

  defp alter_connection(fun) do
    workspace = Foundation.workspace()
    workspace |> Ecto.Changeset.change(connection: fun.(workspace.connection)) |> Repo.update!()
  end
end
