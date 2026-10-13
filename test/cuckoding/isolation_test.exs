defmodule Cuckoding.IsolationTest do
  use Cuckoding.DataCase
  alias Cuckoding.{Agents, Codex, Command, Event, Foundation}

  setup do
    root = Path.join("/private/tmp", "cuckoding-isolation-test-" <> Ecto.UUID.generate())
    File.mkdir!(root)
    path = Path.join(root, "codex")
    File.write!(path, "#!/bin/sh\nexit 1\n")
    File.chmod!(path, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    version(path)
    %{path: path}
  end

  defp version(path, version \\ Codex.isolation_version()) do
    {:ok, _} =
      Foundation.check_codex(Ecto.UUID.generate(), Foundation.workspace().revision, path, true)

    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => version})
  end

  defp start_check(id \\ "codex") do
    {:ok, %{state: "pending"}} =
      Foundation.check_isolation(Ecto.UUID.generate(), Foundation.workspace().revision, true, id)

    {:ok, claim} = Foundation.claim()
    claim
  end

  defp receipt do
    %{
      "status" => "passed",
      "contract" => "codex-isolation-v1",
      "version" => Codex.isolation_version(),
      "children" => for(pid <- 1..5, do: %{"pid" => pid, "spawned_at_ms" => 1000}),
      "elapsed_ms" => 500
    }
  end

  test "requires explicit current executable consent, serializes and scopes the immutable receipt",
       %{path: path} do
    revision = Foundation.workspace().revision
    assert {:error, _} = Foundation.check_isolation(Ecto.UUID.generate(), revision, false)
    key = Ecto.UUID.generate()
    assert {:ok, %{state: "pending"} = command} = Foundation.check_isolation(key, revision, true)
    assert {:ok, ^command} = Foundation.check_isolation(key, revision, true)
    assert Foundation.isolation_current?(command.payload)

    assert {:ok, %{state: "rejected", result: "profile_busy"}} =
             Foundation.discover(Ecto.UUID.generate(), revision)

    {:ok, claim} = Foundation.claim()

    assert {:ok, %{state: "completed"}} =
             Foundation.finish(claim, Map.put(receipt(), "raw", "private-canary"))

    assert Foundation.workspace().codex["isolation"]["status"] == "passed"
    assert Foundation.workspace().connection == %{}
    refute inspect(Repo.all(Event)) =~ "private-canary"
    version(path)
    refute Foundation.isolation_current?(command.payload)
    refute Foundation.workspace().codex["isolation"]

    assert Repo.exists?(
             from e in Event, where: e.kind == "isolation.completed" and e.command_id == ^claim.id
           )
  end

  test "old versions and Cursor cannot borrow another connection's check", %{path: path} do
    version(path, "0.146.0")

    assert {:error, :isolation_unavailable} =
             Foundation.check_isolation(
               Ecto.UUID.generate(),
               Foundation.workspace().revision,
               true
             )

    {:ok, command} =
      Agents.add_and_probe(
        Ecto.UUID.generate(),
        Foundation.workspace().revision,
        "Cursor",
        "cursor",
        path
      )

    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "2026.09.15-d2fe57e"})

    assert {:error, :isolation_unavailable} =
             Foundation.check_isolation(
               Ecto.UUID.generate(),
               Foundation.workspace().revision,
               true,
               command.payload["agent_id"]
             )
  end

  test "named Codex keeps its receipt separate from the legacy profile", %{path: path} do
    {:ok, command} =
      Agents.add_and_probe(
        Ecto.UUID.generate(),
        Foundation.workspace().revision,
        "Other Codex",
        "codex",
        path
      )

    id = command.payload["agent_id"]
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => Codex.isolation_version()})
    claim = start_check(id)
    Foundation.finish(claim, receipt())
    assert Agents.get(id).codex["isolation"]["status"] == "passed"
    refute Foundation.workspace().codex["isolation"]
  end

  test "changed binaries cannot publish a pass", %{path: path} do
    claim = start_check()
    File.write!(path, "#!/bin/sh\necho changed\n")
    refute Foundation.isolation_current?(claim.payload)

    assert Codex.check_isolation(claim.payload["identity"], Path.dirname(path), fn -> true end) ==
             %{"status" => "executable_changed"}

    Foundation.finish(claim, receipt())
    assert Foundation.workspace().codex["isolation"]["status"] == "executable_changed"
  end

  test "cancellation waits for cleanup, retains process identities and refuses success" do
    claim = start_check()
    Foundation.cancel_probe(claim.id)
    refute Foundation.probe_active?(claim)
    assert Foundation.pending?()
    assert {:ok, %{state: "cancelled"}} = Foundation.finish(claim, receipt())
    observed = Foundation.workspace().codex["isolation"]
    assert observed["status"] == "cancelled"
    assert length(observed["children"]) == 5
    refute observed["contract"]
    refute Foundation.pending?()
  end

  test "expired claims cannot report success and restart never replays a check" do
    claim = start_check()
    Repo.update_all(from(c in Command, where: c.id == ^claim.id), set: [lease_until: 1])
    refute Foundation.probe_active?(claim)
    assert {:error, :lost_claim} = Foundation.finish(claim, receipt())
    assert {:ok, %{state: "failed", result: "interrupted", attempts: 1}} = Foundation.claim()
    assert {:ok, nil} = Foundation.claim()
    refute Foundation.workspace().codex["isolation"]
  end

  test "malformed, partial and foreign receipts are never a passing check" do
    public = receipt()

    assert Codex.normalize_isolation(Jason.encode!(Map.put(public, "raw", "private-canary"))) ==
             public

    for bad <- [
          Map.put(public, "contract", "unrestricted"),
          Map.put(public, "version", "unknown"),
          Map.put(public, "children", []),
          Map.put(public, "children", [%{"pid" => "other", "spawned_at_ms" => 1}]),
          Map.put(public, "elapsed_ms", -1),
          %{"status" => "private-canary"}
        ] do
      assert Codex.normalize_isolation(Jason.encode!(bad)) == %{"status" => "invalid_output"}
    end

    assert Codex.normalize_isolation(String.duplicate("x", 2049)) == %{
             "status" => "invalid_output"
           }

    assert Codex.normalize_isolation(~s({"status":"isolation_failed","raw":"private-canary"})) ==
             %{"status" => "isolation_failed"}
  end
end
