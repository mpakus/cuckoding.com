defmodule Cuckoding.DiagnosticsTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Diagnostics
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Plugins.Plugin
  alias Cuckoding.Power.PowerEvent
  alias Cuckoding.Repo

  @canary "CUCKODING_DIAGNOSTICS_SECRET_CANARY"

  test "exports only bounded allowlisted diagnostics and removes canaries" do
    insert_sensitive_fixtures()
    root = temporary_directory()

    assert {:ok, path} =
             Diagnostics.export(
               output_root: root,
               secrets: [@canary],
               now: ~U[2026-09-18 12:00:00.000000Z]
             )

    assert Path.dirname(path) == root
    assert File.stat!(path).mode |> Bitwise.band(0o077) == 0

    assert {:ok, files} = :zip.extract(String.to_charlist(path), [:memory])
    assert Enum.map(files, fn {name, _contents} -> to_string(name) end) == Diagnostics.contents()

    exported = Enum.map_join(files, "\n", fn {_name, contents} -> contents end)
    refute exported =~ @canary
    refute exported =~ "manifest_path"
    refute exported =~ "metadata_json"
    refute exported =~ "public_summary"
    refute exported =~ "payload"
    refute exported =~ "start_identity"
    refute exported =~ "repo_path"
    refute exported =~ "secret_key_base"

    manifest = json_file(files, "manifest.json")
    assert manifest["redaction_policy"] == "allowlist-v1"
    assert "prompts and provider output" in manifest["excluded"]

    assert [%{"key" => "diagnostic-fixture", "health" => "unhealthy"}] =
             json_file(files, "plugins.json")

    assert [%{"kind" => "sleep_gap", "affected_run_count" => 1}] =
             json_file(files, "power-events.json")

    assert [%{"event_type" => "stage.failed"}] = json_file(files, "recent-errors.json")
  end

  test "rejects a symlinked diagnostics directory" do
    parent = temporary_directory()
    outside = temporary_directory()
    File.ln_s!(outside, Path.join(parent, "linked"))

    assert {:error, {:diagnostics_export_failed, :unsafe_output_directory}} =
             Diagnostics.export(output_root: Path.join(parent, "linked"))
  end

  defp insert_sensitive_fixtures do
    Repo.insert!(%Plugin{
      id: Ecto.UUID.generate(),
      key: "diagnostic-fixture",
      name: "Diagnostics fixture",
      kind: "metric_source",
      version: "1.0.0",
      source: "user",
      manifest_path: "/private/#{@canary}/plugin.yml",
      manifest_hash: String.duplicate("a", 64),
      manifest_json: %{"secret" => @canary},
      detected_binaries_json: %{"path" => "/private/#{@canary}"},
      health: "unhealthy",
      detected_at: ~U[2026-09-18 10:00:00.000000Z],
      last_error: @canary
    })

    Repo.insert!(%PowerEvent{
      id: Ecto.UUID.generate(),
      kind: "sleep_gap",
      gap_ms: 5_000,
      affected_runs_json: [Ecto.UUID.generate()],
      metadata_json: %{"detail" => @canary},
      occurred_at: ~U[2026-09-18 10:01:00.000000Z]
    })

    Repo.insert!(%RunEvent{
      run_id: Ecto.UUID.generate(),
      sequence: 1,
      event_type: "stage.failed",
      public_summary: "failed #{@canary}",
      payload: %{"prompt" => @canary},
      occurred_at: ~U[2026-09-18 10:02:00.000000Z]
    })
  end

  defp json_file(files, name) do
    {_name, contents} = Enum.find(files, fn {entry, _contents} -> to_string(entry) == name end)
    Jason.decode!(contents)
  end

  defp temporary_directory do
    directory =
      System.tmp_dir!()
      |> String.replace_prefix("/var/", "/private/var/")
      |> Path.join("cuckoding-diagnostics-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    directory
  end
end
