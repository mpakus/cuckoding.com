defmodule Cuckoding.Diagnostics do
  @moduledoc "Generates a bounded, allowlisted diagnostics archive for user review."

  import Ecto.Query

  alias Cuckoding.Config
  alias Cuckoding.Execution.ProcessRecord
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Plugins.Plugin
  alias Cuckoding.Power.PowerEvent
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo
  alias Cuckoding.Security.Redactor
  alias Cuckoding.Shell

  @archive_entries ~w(manifest.json configuration.json migrations.json plugins.json power-events.json recent-errors.json processes.json)
  @maximum_archive_input_bytes 2_097_152
  @row_limit 200

  def contents, do: @archive_entries

  def export(options \\ []) do
    now = Keyword.get(options, :now, DateTime.utc_now())
    output_root = Keyword.get(options, :output_root, configured_output_root())
    secrets = Keyword.get(options, :secrets, [])

    with :ok <- private_directory(output_root),
         entries <- entries(now, secrets),
         :ok <- bounded(entries),
         {:ok, {_name, archive}} <- :zip.create(~c"cuckoding-diagnostics.zip", entries, [:memory]),
         path <- Path.join(output_root, archive_name(now)),
         :ok <- atomic_write(path, archive) do
      {:ok, path}
    else
      {:error, reason} -> {:error, {:diagnostics_export_failed, reason}}
    end
  end

  defp entries(now, secrets) do
    snapshots = %{
      "manifest.json" => manifest(now),
      "configuration.json" => configuration(),
      "migrations.json" => migrations(),
      "plugins.json" => plugins(),
      "power-events.json" => power_events(),
      "recent-errors.json" => recent_errors(),
      "processes.json" => processes()
    }

    Enum.map(@archive_entries, fn name ->
      body = snapshots |> Map.fetch!(name) |> Redactor.redact(secrets)
      {String.to_charlist(name), Jason.encode!(body, pretty: true) <> "\n"}
    end)
  end

  defp manifest(now) do
    %{
      schema_version: 1,
      generated_at: DateTime.to_iso8601(now),
      application: %{
        name: "Cuckoding",
        version: Application.spec(:cuckoding, :vsn) |> to_string(),
        elixir: System.version(),
        otp: System.otp_release(),
        operating_system: :os.type() |> Tuple.to_list() |> Enum.join("-"),
        architecture: :erlang.system_info(:system_architecture) |> to_string()
      },
      included: @archive_entries -- ["manifest.json"],
      excluded: [
        "repository source and worktree contents",
        "prompts and provider output",
        "credentials and secret values",
        "raw logs, command output, argv, and environment variables",
        "absolute repository, manifest, artifact, and knowledge paths"
      ],
      redaction_policy: "allowlist-v1"
    }
  end

  defp configuration do
    %{
      runtime: Config.safe_snapshot(),
      project_configurations:
        Repo.all(
          from(config in ProjectConfigVersion,
            order_by: [asc: config.project_id, desc: config.revision],
            limit: @row_limit,
            select: %{
              project_id: config.project_id,
              revision: config.revision,
              source_hash: config.source_hash,
              trusted_at: config.trusted_at
            }
          )
        )
        |> Enum.map(&iso_dates/1),
      health: Shell.status()
    }
  end

  defp migrations do
    Repo
    |> Ecto.Migrator.migrations()
    |> Enum.map(fn {status, version, name} ->
      %{status: status, version: version, name: name}
    end)
  end

  defp plugins do
    Repo.all(
      from(plugin in Plugin,
        order_by: plugin.key,
        limit: @row_limit,
        select: %{
          key: plugin.key,
          name: plugin.name,
          kind: plugin.kind,
          version: plugin.version,
          source: plugin.source,
          health: plugin.health,
          detected_at: plugin.detected_at
        }
      )
    )
    |> Enum.map(&iso_dates/1)
  end

  defp power_events do
    Repo.all(
      from(event in PowerEvent,
        order_by: [desc: event.occurred_at, desc: event.id],
        limit: @row_limit,
        select: %{
          id: event.id,
          kind: event.kind,
          gap_ms: event.gap_ms,
          affected_run_count: fragment("json_array_length(?)", event.affected_runs_json),
          occurred_at: event.occurred_at
        }
      )
    )
    |> Enum.map(&iso_dates/1)
  end

  defp recent_errors do
    Repo.all(
      from(event in RunEvent,
        where:
          like(event.event_type, "%failed%") or like(event.event_type, "%error%") or
            like(event.event_type, "%blocked%"),
        order_by: [desc: event.occurred_at, desc: event.id],
        limit: @row_limit,
        select: %{
          id: event.id,
          run_id: event.run_id,
          sequence: event.sequence,
          event_type: event.event_type,
          occurred_at: event.occurred_at
        }
      )
    )
    |> Enum.map(&iso_dates/1)
  end

  defp processes do
    Repo.all(
      from(process in ProcessRecord,
        group_by: process.state,
        order_by: process.state,
        select: %{
          state: process.state,
          count: count(process.id),
          most_recent_end: max(process.ended_at)
        }
      )
    )
    |> Enum.map(&iso_dates/1)
  end

  defp iso_dates(map) do
    Map.new(map, fn
      {key, %DateTime{} = value} -> {key, DateTime.to_iso8601(value)}
      entry -> entry
    end)
  end

  defp bounded(entries) do
    if Enum.sum(Enum.map(entries, fn {_name, contents} -> byte_size(contents) end)) <=
         @maximum_archive_input_bytes,
       do: :ok,
       else: {:error, :bundle_too_large}
  end

  defp private_directory(path) do
    with :ok <- reject_symlink_parents(Path.dirname(path)),
         :ok <- ensure_directory(path) do
      File.chmod(path, 0o700)
    end
  end

  defp ensure_directory(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} -> :ok
      {:error, :enoent} -> File.mkdir_p(path)
      {:ok, _stat} -> {:error, :unsafe_output_directory}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reject_symlink_parents("/"), do: :ok

  defp reject_symlink_parents(path) do
    with :ok <- reject_symlink_parents(Path.dirname(path)) do
      case File.lstat(path) do
        {:ok, %{type: :directory}} -> :ok
        {:error, :enoent} -> :ok
        {:ok, _stat} -> {:error, :unsafe_output_parent}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp atomic_write(path, contents) do
    temporary = path <> ".tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.write(temporary, contents, [:binary, :exclusive]),
         :ok <- File.chmod(temporary, 0o600),
         :ok <- File.rename(temporary, path) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(temporary)
        error
    end
  end

  defp archive_name(now),
    do:
      "cuckoding-diagnostics-#{Calendar.strftime(now, "%Y%m%dT%H%M%SZ")}-#{Ecto.UUID.generate()}.zip"

  defp configured_output_root do
    Application.get_env(:cuckoding, :diagnostics_output_root) ||
      Repo.config()[:database]
      |> Path.expand()
      |> Path.dirname()
      |> Path.join("diagnostics")
  end
end
