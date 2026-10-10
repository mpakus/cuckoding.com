defmodule Cuckoding.ConnectionTest do
  use Cuckoding.DataCase
  alias Cuckoding.{Codex, Command, Event, Foundation, Storage}

  setup do
    root = Path.join("/private/tmp", "cuckoding-connection-" <> Ecto.UUID.generate())
    File.mkdir!(root)
    path = Path.join(root, "codex")
    File.write!(path, "#!/bin/sh\nexit 1\n")
    File.chmod!(path, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, path: path}
  end

  defp ready(path) do
    {:ok, _} =
      Foundation.check_codex(Ecto.UUID.generate(), Foundation.workspace().revision, path, true)

    {:ok, claim} = Foundation.claim()
    {:ok, _} = Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})
  end

  defp inspect_profile do
    {:ok, _} =
      Foundation.inspect_codex(Ecto.UUID.generate(), Foundation.workspace().revision, true)

    {:ok, claim} = Foundation.claim()
    claim
  end

  defp catalog do
    %{
      "status" => "checked",
      "authorization" => "chatgpt",
      "catalog_status" => "fresh",
      "models" => [
        %{
          "id" => "test-model",
          "model" => "test-model",
          "name" => "Test model",
          "efforts" => ["medium"],
          "default_effort" => "medium",
          "input_modalities" => ["text"],
          "default" => true
        }
      ]
    }
  end

  test "inspection requires consent, current readiness and an idempotent command", %{path: path} do
    assert {:error, :version_required} = Foundation.inspect_codex(Ecto.UUID.generate(), 0, true)
    ready(path)
    key = Ecto.UUID.generate()
    assert {:error, :confirmation_required} = Foundation.inspect_codex(key, 1, false)
    assert {:ok, command} = Foundation.inspect_codex(key, 1, true)
    assert {:ok, ^command} = Foundation.inspect_codex(key, 1, true)
    assert Foundation.pending_probe("inspect_codex").id == command.id
    File.write!(path, "#!/bin/sh\necho changed\n")
    assert {:error, :version_required} = Foundation.inspect_codex(Ecto.UUID.generate(), 1, true)
    assert Repo.aggregate(from(c in Command, where: c.kind == "inspect_codex"), :count) == 1
  end

  test "catalog survives reload and failed refresh without rewriting account status", %{
    path: path
  } do
    ready(path)
    claim = inspect_profile()
    result = catalog() |> Map.put("email", "fixture-secret") |> Map.put("raw", "fixture-secret")
    assert {:ok, _} = Foundation.finish(claim, result)
    saved = Foundation.workspace().connection
    assert saved["authorization"] == "chatgpt"
    assert saved["source"] == "codex-app-server/model/list"
    assert saved["fetched_at"]
    assert length(saved["models"]) == 1
    assert Foundation.workspace().codex["version"] == "0.146.0"
    refute Jason.encode!(saved) =~ "fixture-secret"

    assert {:ok, _} =
             Foundation.finish(inspect_profile(), %{
               "status" => "checked",
               "authorization" => "chatgpt",
               "catalog_status" => "failed",
               "catalog_error" => "fixture-secret"
             })

    stale = Foundation.workspace().connection
    assert stale["catalog_status"] == "stale"
    assert stale["authorization"] == "chatgpt"
    assert stale["models"] == saved["models"]
    assert stale["fetched_at"] == saved["fetched_at"]
    refute inspect(Repo.all(Event)) =~ "fixture-secret"

    assert {:ok, _} = Foundation.finish(inspect_profile(), %{"status" => "timeout"})
    assert Foundation.workspace().connection["models"] == saved["models"]

    assert Foundation.workspace().connection["authorization_checked_at"] ==
             stale["authorization_checked_at"]

    assert {:ok, _} =
             Foundation.finish(inspect_profile(), %{
               "status" => "checked",
               "authorization" => "not_connected",
               "catalog_status" => "not_requested"
             })

    assert Foundation.workspace().connection["models"] == []
    assert Foundation.workspace().connection["authorization"] == "not_connected"
  end

  test "normalization rejects malformed fields, duplicate rows, large frames and unknown errors" do
    assert %{"status" => "invalid_output"} =
             Codex.normalize_connection(String.duplicate("x", 524_289))

    assert %{"status" => "invalid_output"} =
             Codex.normalize_connection(~s({"status":"fixture-secret"}))

    for rows <- [[%{}], catalog()["models"] ++ catalog()["models"], [%{"id" => "<script>"}]] do
      result =
        catalog() |> Map.put("models", rows) |> Jason.encode!() |> Codex.normalize_connection()

      assert result["authorization"] == "chatgpt"
      assert result["catalog_status"] == "failed"
      refute result["models"]
    end

    result =
      catalog()
      |> put_in(["models", Access.at(0), "raw"], "fixture-secret")
      |> Jason.encode!()
      |> Codex.normalize_connection()

    refute Jason.encode!(result) =~ "fixture-secret"
  end

  test "full catalogs retain additional models and reject malformed visibility", %{path: path} do
    ready(path)
    visible = hd(catalog()["models"])

    additional =
      Map.merge(visible, %{"id" => "additional", "model" => "additional", "hidden" => true})

    result =
      catalog()
      |> Map.put("models", [visible, additional])
      |> Jason.encode!()
      |> Codex.normalize_connection()

    assert result["catalog_status"] == "fresh"
    assert {:ok, _} = Foundation.finish(inspect_profile(), result)
    assert Foundation.workspace().connection["models"] == [visible, additional]

    for flag <- [nil, "false", 1] do
      invalid =
        catalog()
        |> Map.put("models", [Map.put(visible, "hidden", flag)])
        |> Jason.encode!()
        |> Codex.normalize_connection()

      assert invalid["catalog_status"] == "failed"
      assert {:ok, _} = Foundation.finish(inspect_profile(), invalid)
      assert Foundation.workspace().connection["models"] == [visible, additional]
    end
  end

  test "interrupted inspections never replay; cancellation refuses a late catalog", %{path: path} do
    ready(path)
    {:ok, _} = Foundation.inspect_codex(Ecto.UUID.generate(), 1, true)
    {:ok, claim} = Foundation.claim(1_000)
    assert {:ok, nil} = Foundation.claim(20_999)

    assert {:ok, %{state: "failed", result: "interrupted", attempts: 1}} =
             Foundation.claim(21_001)

    assert {:error, :lost_claim} = Foundation.finish(claim, catalog())
    assert Foundation.workspace().connection == %{}
    claim = inspect_profile()
    Foundation.cancel_probe(claim.id)
    assert {:error, :lost_claim} = Foundation.finish(claim, catalog())
    assert Foundation.last_probe("inspect_codex").state == "cancelled"
    refute Foundation.pending_probe("inspect_codex")
  end

  test "a new executable identity cannot inherit another catalog", %{path: path} do
    ready(path)
    Foundation.finish(inspect_profile(), catalog())
    File.write!(path, "#!/bin/sh\necho new-binary\n")
    ready(path)
    assert Foundation.workspace().connection == %{}
  end

  test "catalog freshness expires after 24 hours without changing its stored observation" do
    time = ~U[2026-10-07 00:00:00Z]
    connection = %{"catalog_status" => "fresh", "fetched_at" => DateTime.to_iso8601(time)}
    assert Foundation.catalog_status(connection, DateTime.add(time, 86_399)) == "fresh"
    assert Foundation.catalog_status(connection, DateTime.add(time, 86_400)) == "stale"
    assert Foundation.catalog_status(connection, DateTime.add(time, -1)) == "stale"
    assert Foundation.catalog_status(%{connection | "fetched_at" => "bad"}, time) == "stale"
    assert Foundation.catalog_status(%{"catalog_status" => "stale"}, time) == "stale"
  end

  test "saved model choices are durable, scoped, atomic and idempotent without provider usage", %{
    path: path
  } do
    ready(path)
    Foundation.finish(inspect_profile(), catalog())
    workspace = Foundation.workspace()
    key = Ecto.UUID.generate()

    assert {:ok, saved} =
             Foundation.save_agent_models(
               key,
               workspace.revision,
               workspace.connection["command_id"],
               ["test-model"]
             )

    assert saved.state == "completed"
    assert Foundation.saved_agent_models() == saved
    assert saved.payload["models"] == workspace.connection["models"]
    assert Foundation.workspace().revision == workspace.revision + 1

    assert {:ok, ^saved} =
             Foundation.save_agent_models(
               key,
               workspace.revision,
               workspace.connection["command_id"],
               ["test-model"]
             )

    assert {:error, :key_conflict} =
             Foundation.save_agent_models(key, workspace.revision, "foreign", ["test-model"])

    assert {:ok, nil} = Foundation.claim()
    assert hd(Foundation.events()).kind == "agent_models.saved"

    for ids <- [[], ["test-model", "test-model"], [%{}], "test-model"] do
      assert {:error, :invalid_models} =
               Foundation.save_agent_models(
                 Ecto.UUID.generate(),
                 3,
                 workspace.connection["command_id"],
                 ids
               )
    end

    for {expected, connection, ids, reason} <- [
          {2, workspace.connection["command_id"], ["test-model"], "stale_revision"},
          {3, "foreign", ["test-model"], "model_refresh_required"},
          {3, workspace.connection["command_id"], ["invented"], "model_refresh_required"}
        ] do
      assert {:ok, %{state: "rejected", result: ^reason}} =
               Foundation.save_agent_models(Ecto.UUID.generate(), expected, connection, ids)
    end

    assert Foundation.saved_agent_models() == saved
    Foundation.finish(inspect_profile(), %{"status" => "timeout"})
    workspace = Foundation.workspace()

    assert {:ok, %{state: "rejected", result: "model_refresh_required"}} =
             Foundation.save_agent_models(
               Ecto.UUID.generate(),
               workspace.revision,
               workspace.connection["command_id"],
               ["test-model"]
             )

    assert Foundation.saved_agent_models() == saved
  end

  test "private profile is stable and rejects redirected storage", %{root: root} do
    previous = Application.get_env(:cuckoding, :data_dir)
    Application.put_env(:cuckoding, :data_dir, Path.join(root, "app"))

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cuckoding, :data_dir, previous),
        else: Application.delete_env(:cuckoding, :data_dir)
    end)

    path = Storage.codex_profile!()
    assert path == Storage.codex_profile!()
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o700
    File.rmdir!(path)
    File.ln_s!(root, path)
    assert_raise RuntimeError, ~r/symbolic/, fn -> Storage.codex_profile!() end
  end
end
