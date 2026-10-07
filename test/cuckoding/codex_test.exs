defmodule Cuckoding.CodexTest do
  use Cuckoding.DataCase
  alias Cuckoding.{Codex, Command, Event, Foundation, Storage}

  setup do
    root = Path.join("/private/tmp", "ccoding-codex-test-" <> Ecto.UUID.generate())
    File.mkdir!(root)
    executable = Path.join(root, "codex")
    File.write!(executable, "#!/bin/sh\nexit 1\n")
    File.chmod!(executable, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, executable: executable}
  end

  test "manual paths require consent, metadata and an idempotent intent", %{executable: path} do
    key = Ecto.UUID.generate()
    assert {:error, :confirmation_required} = Foundation.check_codex(key, 0, path, false)
    assert Repo.aggregate(Command, :count) == 0

    for invalid <- [
          "codex",
          "/does-not-exist",
          path <> "\n",
          Path.dirname(path),
          path <> "/../codex"
        ] do
      assert {:error, :invalid_executable} = Foundation.check_codex(key, 0, invalid, true)
    end

    assert {:ok, command} = Foundation.check_codex(key, 0, path, true)
    assert {:ok, ^command} = Foundation.check_codex(key, 0, path, true)
    assert {:error, :key_conflict} = Foundation.discover(key, 0)
    assert Repo.aggregate(Command, :count) == 1
    assert Repo.aggregate(Event, :count) == 1
    assert Foundation.pending_probe().id == command.id
  end

  test "only bounded public output becomes readiness evidence" do
    assert %{"status" => "supported", "version" => "0.146.0", "pid" => 123} =
             Codex.normalize(
               ~s({"status":"observed","version":"0.146.0","pid":123,"raw":"fixture-secret"})
             )

    for version <- ["0.145.0", "0.147.0", "1.0.0"] do
      assert %{"status" => "unsupported"} =
               Codex.normalize(Jason.encode!(%{status: "observed", version: version}))
    end

    for output <- [
          "bad",
          "[]",
          String.duplicate("x", 1025),
          ~s({"status":"observed","version":"fixture-secret"}),
          ~s({"status":"observed","version":null}),
          ~s({"status":"fixture-secret"})
        ] do
      assert Codex.normalize(output) == %{"status" => "invalid_output"}
    end

    assert Codex.normalize(
             ~s({"status":"timeout","raw":"fixture-secret","pid":"fixture-secret","elapsed_ms":-1})
           ) == %{"status" => "timeout"}
  end

  test "a changed executable is never launched", %{executable: path, root: root} do
    {:ok, identity} = Codex.executable(path)
    File.write!(path, "#!/bin/sh\necho this-must-not-run\n")
    assert Codex.probe(identity, root, fn -> true end) == %{"status" => "executable_changed"}
  end

  test "readiness survives reads; account status remains separate", %{executable: path} do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, path, true)
    {:ok, claim} = Foundation.claim()

    result =
      Codex.normalize(
        ~s({"status":"observed","version":"0.146.0","elapsed_ms":25,"raw":"fixture-secret"})
      )

    assert {:ok, %{state: "completed"}} = Foundation.finish(claim, result)
    assert Foundation.workspace().revision == 1
    assert Foundation.workspace().codex["authorization"] == "not_connected"
    assert Foundation.workspace().codex["version"] == "0.146.0"
    assert Foundation.workspace().tools == %{}
    refute Jason.encode!(Foundation.workspace().codex) =~ "fixture-secret"
    refute inspect(Repo.all(Event)) =~ "fixture-secret"

    assert {:ok, %{state: "rejected"}} =
             Foundation.check_codex(Ecto.UUID.generate(), 0, path, true)
  end

  test "interrupted probes require a new consented command instead of automatic replay", %{
    executable: path
  } do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, path, true)
    {:ok, claim} = Foundation.claim(1_000)
    assert {:ok, nil} = Foundation.claim(2_000)

    assert {:ok, %{state: "failed", result: "interrupted", attempts: 1}} =
             Foundation.claim(11_001)

    assert {:ok, nil} = Foundation.claim(11_002)
    refute Foundation.probe_active?(claim)
    assert {:error, :lost_claim} = Foundation.finish(claim, %{"status" => "supported"})
    assert Foundation.workspace().codex == %{}
  end

  test "cancellation is durable and late results cannot overwrite it", %{executable: path} do
    {:ok, command} = Foundation.check_codex(Ecto.UUID.generate(), 0, path, true)
    {:ok, claim} = Foundation.claim()
    assert Foundation.probe_active?(claim)
    assert {:ok, _} = Foundation.cancel_probe(command.id)
    assert {:ok, _} = Foundation.cancel_probe(command.id)
    assert Foundation.last_probe().state == "cancelled"
    refute Foundation.pending_probe()
    assert {:error, :lost_claim} = Foundation.finish(claim, %{"status" => "supported"})
    assert Repo.aggregate(from(e in Event, where: e.kind == "codex.cancelled"), :count) == 1
  end

  test "scratch paths are private, scoped and refuse links", %{root: root} do
    previous = Application.get_env(:cuckoding, :data_dir)
    Application.put_env(:cuckoding, :data_dir, Path.join(root, "app"))

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cuckoding, :data_dir, previous),
        else: Application.delete_env(:cuckoding, :data_dir)
    end)

    id = Ecto.UUID.generate()
    path = Storage.probe_directory!(id, 1)
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o700
    File.rmdir!(path)
    File.ln_s!(root, path)
    assert_raise RuntimeError, ~r/symbolic/, fn -> Storage.probe_directory!(id, 1) end
    assert_raise MatchError, fn -> Storage.probe_directory!("../outside", 1) end
  end
end
