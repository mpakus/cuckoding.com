defmodule Cuckoding.SecurityTest do
  use Cuckoding.DataCase, async: false

  import Ecto.Query

  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.FakeCommandRunner
  alias Cuckoding.FakeSecretStore
  alias Cuckoding.Security.Audit
  alias Cuckoding.Security.AuditEvent
  alias Cuckoding.Security.KeychainSecretStore
  alias Cuckoding.Security.Redactor
  alias Cuckoding.Security.SecretAccessAudit
  alias Cuckoding.Security.SecretStore

  @canary "CUCKODING_CANARY_do-not-persist_7fcb34"

  setup do
    previous = Application.get_env(:cuckoding, :secret_store)
    Application.put_env(:cuckoding, :secret_store, FakeSecretStore)
    FakeSecretStore.reset()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cuckoding, :secret_store, previous),
        else: Application.delete_env(:cuckoding, :secret_store)
    end)
  end

  test "opaque references are audited without persisting the raw value" do
    assert {:ok, reference} = SecretStore.put(@canary)
    assert reference =~ ~r/^keychain:[0-9a-f-]+$/
    refute reference =~ @canary

    assert {:ok, @canary} =
             SecretStore.fetch(reference, "vcs.push", run_id: Ecto.UUID.generate())

    audit = Repo.one!(SecretAccessAudit)
    assert audit.secret_ref == reference
    assert audit.purpose == "vcs.push"
    refute inspect(audit) =~ @canary

    assert :ok = SecretStore.delete(reference)
    assert {:error, :not_found} = SecretStore.fetch(reference, "vcs.push")
    assert Repo.aggregate(SecretAccessAudit, :count) == 1
  end

  test "Keychain command puts the value on stdin and never argv" do
    reference = "keychain:" <> Ecto.UUID.generate()
    options = [command_runner: FakeCommandRunner, owner: self()]

    assert :ok = KeychainSecretStore.put(reference, @canary, options)
    assert_receive {:command, "/usr/bin/security", args, input}
    refute inspect(args) =~ @canary
    assert input == @canary <> "\n"

    assert args == [
             "add-generic-password",
             "-U",
             "-s",
             "com.cuckoding.secret",
             "-a",
             reference,
             "-w"
           ]

    assert {:ok, @canary} =
             KeychainSecretStore.fetch(reference,
               command_runner: FakeCommandRunner,
               owner: self(),
               result: {:ok, @canary <> "\n"}
             )

    assert_receive {:command, "/usr/bin/security", fetch_args, ""}
    refute inspect(fetch_args) =~ @canary
  end

  test "canaries are removed before persistence, broadcast, export, artifacts, and knowledge" do
    raw = %{
      "log" => "prefix #{@canary} suffix",
      "authorization" => "Bearer #{@canary}",
      "nested" => [%{"token" => @canary}, @canary],
      "artifact" => %{"body" => @canary},
      "export" => %{"rows" => [@canary]},
      "knowledge" => %{"content" => "candidate #{@canary}"},
      "environment" => %{"SAFE" => "value", "SECRET" => @canary},
      "argv" => ["--token", @canary]
    }

    redacted = Redactor.redact(raw, [@canary])
    refute inspect(redacted) =~ @canary
    assert redacted["authorization"] == "[REDACTED]"
    assert redacted["environment"] == "[REDACTED]"
    assert redacted["argv"] == "[REDACTED]"

    assert {:ok, {event, nil}} =
             EventStore.append(Ecto.UUID.generate(), %{
               event_type: "test.redacted",
               public_summary: redacted["log"],
               payload: redacted
             })

    persisted = Repo.get!(RunEvent, event.id)
    refute inspect(persisted) =~ @canary

    broadcast_payload = Redactor.redact(raw, [@canary])
    send(self(), {:broadcast, broadcast_payload})
    assert_receive {:broadcast, safe_payload}
    refute inspect(safe_payload) =~ @canary
  end

  test "authentication rejection audits are bounded, secret-free, and append-only" do
    assert {:ok, event} =
             Audit.record(
               "auth.browser_token_rejected",
               "GET",
               "/open",
               401
             )

    assert event.path == "/open"
    refute inspect(event) =~ @canary

    assert {:error, :invalid_security_audit} =
             Audit.record("auth.unknown", "GET", "/open?token=#{@canary}", 401)

    assert_raise Exqlite.Error, ~r/append-only/, fn ->
      Repo.update_all(from(item in AuditEvent, where: item.id == ^event.id),
        set: [path: "/changed"]
      )
    end

    assert_raise Exqlite.Error, ~r/append-only/, fn ->
      Repo.delete_all(from(item in AuditEvent, where: item.id == ^event.id))
    end
  end
end
