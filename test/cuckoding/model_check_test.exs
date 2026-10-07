defmodule Cuckoding.ModelCheckTest do
  use Cuckoding.DataCase
  alias Cuckoding.{Codex, Command, Event, Foundation}

  setup do
    root = Path.join("/private/tmp", "cuckoding-model-test-" <> Ecto.UUID.generate())
    File.mkdir!(root)
    path = Path.join(root, "codex")
    File.write!(path, "#!/bin/sh\nexit 1\n")
    File.chmod!(path, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, path, true)
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})
    refresh()
    %{path: path}
  end

  defp refresh do
    {:ok, _} =
      Foundation.inspect_codex(Ecto.UUID.generate(), Foundation.workspace().revision, true)

    {:ok, claim} = Foundation.claim()

    Foundation.finish(claim, %{
      "status" => "checked",
      "authorization" => "chatgpt",
      "catalog_status" => "fresh",
      "models" => [
        %{
          "id" => "test-id",
          "model" => "test-model",
          "name" => "Test model",
          "efforts" => ["high", "low"],
          "default_effort" => "high",
          "input_modalities" => ["text"],
          "default" => true
        }
      ]
    })
  end

  defp start_check do
    {:ok, command} =
      Foundation.check_model(
        Ecto.UUID.generate(),
        Foundation.workspace().revision,
        "test-id",
        true
      )

    assert command.state == "pending"
    {:ok, claim} = Foundation.claim()
    claim
  end

  defp receipt do
    %{
      "status" => "passed",
      "requested_model" => "test-model",
      "observed_model" => "test-model",
      "effort" => "low",
      "thread_id" => Ecto.UUID.generate(),
      "turn_id" => Ecto.UUID.generate(),
      "grant" => "scratch-read-only-v1",
      "elapsed_ms" => 20
    }
  end

  test "consent and fresh identity are required; the selected model is snapshotted once", %{
    path: path
  } do
    key = Ecto.UUID.generate()
    assert {:error, :confirmation_required} = Foundation.check_model(key, 2, "test-id", false)
    assert {:error, :model_refresh_required} = Foundation.check_model(key, 2, "unknown", true)
    assert {:ok, command} = Foundation.check_model(key, 2, "test-id", true)
    assert {:ok, ^command} = Foundation.check_model(key, 2, "test-id", true)
    assert command.payload["model"] == "test-model"
    assert command.payload["effort"] == "low"
    assert Foundation.model_check_current?(command.payload)

    assert {:ok, %{state: "rejected", result: "profile_busy"}} =
             Foundation.discover(Ecto.UUID.generate(), 2)

    assert {:ok, %{state: "rejected", result: "profile_busy"}} =
             Foundation.authorize_codex(Ecto.UUID.generate(), 2, :logout, true)

    File.write!(path, "#!/bin/sh\necho changed\n")

    assert {:error, :version_required} =
             Foundation.check_model(Ecto.UUID.generate(), 2, "test-id", true)

    assert Codex.check_model(
             command.payload["identity"],
             Path.dirname(path),
             Path.dirname(path),
             "test-model",
             "low",
             fn -> true end
           ) == %{"status" => "executable_changed"}
  end

  test "stale catalogs and pending discovery cannot authorize inference" do
    connection = Foundation.workspace().connection

    Foundation.workspace()
    |> Ecto.Changeset.change(
      connection: Map.put(connection, "fetched_at", "2020-01-01T00:00:00Z")
    )
    |> Repo.update!()

    assert {:ok, %{state: "rejected", result: "model_refresh_required"}} =
             Foundation.check_model(Ecto.UUID.generate(), 2, "test-id", true)

    Foundation.workspace() |> Ecto.Changeset.change(connection: connection) |> Repo.update!()
    {:ok, _} = Foundation.discover(Ecto.UUID.generate(), 2)

    assert {:ok, %{state: "rejected", result: "profile_busy"}} =
             Foundation.check_model(Ecto.UUID.generate(), 2, "test-id", true)
  end

  test "only matching public completion persists and refresh invalidates its current projection" do
    claim = start_check()
    result = Map.merge(receipt(), %{"raw" => "fixture-secret", "reasoning" => "fixture-secret"})
    assert {:ok, %{state: "completed"}} = Foundation.finish(claim, result)
    saved = Foundation.workspace().connection["model_check"]
    assert saved["status"] == "passed"
    assert saved["observed_model"] == saved["requested_model"]
    assert saved["command_id"] == claim.id
    refute inspect(Foundation.workspace()) =~ "fixture-secret"
    refute inspect(Repo.all(Event)) =~ "fixture-secret"
    refresh()
    refute Foundation.workspace().connection["model_check"]
    refute Foundation.model_check_current?(claim.payload)

    assert Repo.exists?(
             from e in Event,
               where: e.kind == "model_check.completed" and e.command_id == ^claim.id
           )
  end

  test "model drift and altered connection snapshots cannot become a pass" do
    for change <- [:model, :connection] do
      claim = start_check()
      result = receipt()

      result =
        if change == :model do
          Map.put(result, "observed_model", "another-model")
        else
          connection =
            Map.put(Foundation.workspace().connection, "command_id", Ecto.UUID.generate())

          Foundation.workspace()
          |> Ecto.Changeset.change(connection: connection)
          |> Repo.update!()

          result
        end

      Foundation.finish(claim, result)
      assert Foundation.workspace().connection["model_check"]["status"] == "model_mismatch"
      refute Foundation.workspace().connection["model_check"]["observed_model"]
      refresh()
    end
  end

  test "running cancellation holds exclusion until cleanup and refuses late success" do
    claim = start_check()
    Foundation.cancel_probe(claim.id)
    assert Foundation.pending_probe("check_codex_model").state == "cancelling"
    refute Foundation.probe_active?(claim)

    assert {:ok, %{state: "rejected", result: "profile_busy"}} =
             Foundation.inspect_codex(Ecto.UUID.generate(), 2, true)

    assert {:ok, %{state: "cancelled"}} = Foundation.finish(claim, receipt())
    assert Foundation.workspace().connection["model_check"]["status"] == "cancelled"
    refute Foundation.workspace().connection["model_check"]["thread_id"]
    refute Foundation.pending?()
  end

  test "expired inference is interrupted once, never replayed" do
    {:ok, _} = Foundation.check_model(Ecto.UUID.generate(), 2, "test-id", true)
    {:ok, claim} = Foundation.claim(1_000)
    assert {:ok, nil} = Foundation.claim(140_999)

    assert {:ok, %{state: "failed", result: "interrupted", attempts: 1}} =
             Foundation.claim(141_001)

    assert {:ok, nil} = Foundation.claim(141_002)
    assert {:error, :lost_claim} = Foundation.finish(claim, receipt())
    refute Foundation.workspace().connection["model_check"]
    assert Repo.aggregate(from(c in Command, where: c.kind == "check_codex_model"), :count) == 1
  end

  test "receipt normalization rejects missing binding, raw failures and oversized data" do
    public = receipt()

    assert Codex.normalize_model_check(Jason.encode!(Map.put(public, "raw", "fixture-secret"))) ==
             public

    for bad <- [
          Map.delete(public, "thread_id"),
          Map.put(public, "turn_id", "fixture-secret"),
          Map.put(public, "grant", "full-access"),
          %{"status" => "fixture-secret"},
          %{"status" => "awaiting_login", "auth_url" => "fixture-secret"}
        ] do
      assert Codex.normalize_model_check(Jason.encode!(bad)) == %{"status" => "invalid_output"}
    end

    assert Codex.normalize_model_check(String.duplicate("x", 1025)) == %{
             "status" => "invalid_output"
           }

    assert Codex.normalize_model_check(~s({"status":"turn_failed","raw":"fixture-secret"})) == %{
             "status" => "turn_failed"
           }
  end
end
