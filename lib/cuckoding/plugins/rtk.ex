defmodule Cuckoding.Plugins.RTK do
  @moduledoc "Frozen RTK policy and isolated, optional shell-output optimization."

  import Ecto.Query
  import Bitwise, only: [band: 2]

  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Plugins.Activation
  alias Cuckoding.Plugins.Plugin
  alias Cuckoding.Repo

  @version "0.49.0"
  @directories ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
  @fallbacks %{
    "claude_code" =>
      "Claude 2.1.142 bare mode disables hooks to preserve configuration isolation.",
    "cursor_agent" =>
      "Cursor 2026.09.15 hook permission preservation and isolated loading are not verified.",
    "codex" => "Codex 0.146.0 strict configuration has no verified run-owned hook trust flow."
  }

  def discover(options \\ []) do
    paths = Enum.map(Keyword.get(options, :directories, @directories), &Path.join(&1, "rtk"))
    runner = Keyword.get(options, :command_runner, &System.cmd/3)

    case paths |> Enum.filter(&executable?/1) |> Enum.map(&detect_version(&1, runner)) do
      [] ->
        %{
          health: "missing",
          binaries: %{},
          last_error: "RTK executable not found in approved locations"
        }

      results ->
        Enum.find(results, &(&1.health == "available")) || hd(results)
    end
  end

  defp detect_version(path, runner) do
    case runner.(path, ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version =
          case Regex.run(~r/\Artk (\d+\.\d+\.\d+)\z/, String.trim(output),
                 capture: :all_but_first
               ) do
            [version] -> version
            _other -> nil
          end

        health =
          cond do
            version == @version -> "available"
            is_nil(version) -> "unhealthy"
            true -> "version_mismatch"
          end

        binary = %{
          "path" => path,
          "version" => version,
          "sha256" => digest_file(path)
        }

        %{
          health: health,
          binaries: %{"rtk" => binary},
          last_error: if(health != "available", do: "Supported RTK version: #{@version}")
        }

      _other ->
        %{health: "unhealthy", binaries: %{}, last_error: "RTK version check failed"}
    end
  rescue
    _error -> %{health: "unhealthy", binaries: %{}, last_error: "RTK version check failed"}
  end

  def snapshot(board, roles) do
    case Repo.get_by(Plugin, key: "rtk") do
      nil ->
        %{"rtk" => %{"enabled" => false, "reason" => "RTK has not been enabled."}}

      %Plugin{source: "bundled"} = plugin ->
        activations = Repo.all(from a in Activation, where: a.plugin_id == ^plugin.id)
        base = [{"board", board.id}, {"project", board.project_id}, {"global", nil}]

        %{
          "rtk" => %{
            "plugin_id" => plugin.id,
            "binary" => plugin.detected_binaries_json["rtk"],
            "health" => plugin.health,
            "manifest_hash" => plugin.manifest_hash,
            "default" => selection(activations, base),
            "roles" =>
              Map.new(roles, &{&1.role_key, selection(activations, [{"role", &1.id} | base])})
          }
        }

      _untrusted ->
        %{
          "rtk" => %{
            "enabled" => false,
            "reason" => "Only the bundled RTK integration is accepted."
          }
        }
    end
  end

  defp selection(activations, scopes) do
    matches =
      Enum.map(scopes, fn {type, id} ->
        Enum.find(activations, &(&1.scope_type == type and &1.scope_id == id))
      end)

    selected = Enum.find(matches, &(&1 && not &1.enabled)) || Enum.find(matches, & &1)

    if selected do
      %{
        "enabled" => selected.enabled,
        "activation_id" => selected.id,
        "scope" => selected.scope_type,
        "config" => selected.config_json,
        "permissions" => selected.permissions_json
      }
    else
      %{"enabled" => false}
    end
  end

  def policy(run, role_key \\ nil) do
    snapshot = Map.get(run.plugin_snapshot_json, "rtk", %{})
    selected = get_in(snapshot, ["roles", role_key]) || snapshot["default"] || snapshot
    Map.merge(Map.take(snapshot, ["binary", "health", "manifest_hash"]), selected)
  end

  def status(policy, adapter \\ nil) do
    cond do
      policy["enabled"] != true ->
        {"Disabled", "RTK was not enabled for this scope when the run was prepared."}

      get_in(policy, ["config", "mode"]) == "passthrough" ->
        {"Disabled", "This scope requests unfiltered output."}

      get_in(policy, ["permissions", "host_process"]) != true ->
        {"Disabled", "This scope does not grant host process access."}

      policy["preparation_error"] == true ->
        {"Unavailable", "Isolated RTK storage could not be prepared; use ordinary commands."}

      not available?(policy["binary"]) ->
        {"Unavailable",
         "The recorded RTK executable is missing, changed, or unsupported. Commands continue without filtering."}

      true ->
        {"Instructions only",
         Map.get(
           @fallbacks,
           adapter,
           "Automatic agent hooks require verified permission, trust and isolation checks. Native editing tools remain available."
         )}
    end
  end

  def capability(adapter),
    do: %{"mode" => "instructions_only", "reason" => Map.fetch!(@fallbacks, adapter)}

  def available?(%{"path" => path, "version" => @version, "sha256" => hash})
      when is_binary(path) and is_binary(hash),
      do: executable?(path) and digest_file(path) == hash

  def available?(_binary), do: false

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} -> band(mode, 0o111) != 0
      _other -> false
    end
  end

  defp digest_file(path) do
    case File.read(path) do
      {:ok, contents} -> :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
      _other -> nil
    end
  end

  def configure(request, run, role_key) do
    policy = stage_policy(run, role_key, request.attempt_id)

    %{
      request
      | plugins: [
          %{"kind" => "shell_filter", "key" => "rtk", "policy" => policy} | request.plugins
        ]
    }
    |> prepare_request()
  end

  defp stage_policy(run, role_key, attempt_id) do
    recorded =
      Repo.one(
        from e in Cuckoding.Execution.RunEvent,
          where: e.run_id == ^run.id and e.event_type == "rtk.configuration",
          where: fragment("json_extract(?, '$.stage_attempt_id') = ?", e.payload, ^attempt_id),
          order_by: e.sequence,
          limit: 1
      )

    if recorded do
      recorded.payload["policy"]
    else
      base = policy(run, role_key)
      plugin_id = get_in(run.plugin_snapshot_json, ["rtk", "plugin_id"])

      stage =
        if plugin_id,
          do:
            Repo.get_by(Activation,
              plugin_id: plugin_id,
              scope_type: "stage",
              scope_id: attempt_id
            )

      narrow_stage(base, stage)
    end
  end

  defp narrow_stage(base, nil), do: base

  defp narrow_stage(base, stage) do
    permissions =
      Map.put(
        base["permissions"] || %{},
        "host_process",
        get_in(base, ["permissions", "host_process"]) == true and
          stage.permissions_json["host_process"] == true
      )

    config =
      if stage.config_json["mode"] == "passthrough",
        do: %{"mode" => "passthrough"},
        else: base["config"] || %{}

    base
    |> Map.put("enabled", base["enabled"] == true and stage.enabled)
    |> Map.put("permissions", permissions)
    |> Map.put("config", config)
    |> Map.put("stage_activation_id", stage.id)
  end

  def record_request(request, adapter) do
    key =
      case adapter do
        Cuckoding.Adapters.Codex -> "codex"
        Cuckoding.Adapters.ClaudeCode -> "claude_code"
        Cuckoding.Adapters.CursorAgent -> "cursor_agent"
        _other -> nil
      end

    {mode, reason} = status(request_policy(request), key)

    case EventStore.append(request.run_id, %{
           event_type: "rtk.configuration",
           public_summary: "RTK: #{mode} — #{reason}",
           payload: %{
             "stage_attempt_id" => request.attempt_id,
             "correlation_id" => request.correlation_id,
             "mode" => mode,
             "reason" => reason,
             "policy" => request_policy(request),
             "coverage" => "unknown"
           }
         }) do
      {:ok, _event} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def settings_status(plugin) do
    activation = Enum.find(plugin.activations, &(&1.scope_type == "global"))

    policy = %{
      "enabled" => activation && activation.enabled,
      "config" => if(activation, do: activation.config_json, else: %{}),
      "permissions" => if(activation, do: activation.permissions_json, else: %{}),
      "binary" => plugin.detected_binaries_json["rtk"]
    }

    status(policy)
  end

  def instructions(request) do
    policy = request_policy(request)
    {mode, reason} = status(policy)

    if mode == "Instructions only" do
      path = wrapper(request.run_dir)

      """


      RTK: #{mode}. #{reason}
      Use #{quote_shell(path)} for supported repository shell commands (git status/diff/log, rg, ls, tests).
      This app-owned launcher uses the verified RTK #{get_in(policy, ["binary", "version"])} at #{get_in(policy, ["binary", "path"])} with isolated state.
      Use #{quote_shell(path)} rewrite '<command>' to check support without executing it. Preserve quoting and compound-command behavior.
      Use #{quote_shell(path)} proxy <command> only for exact or streaming output or when filtering would change semantics; state the reason publicly.
      Keep native editing tools available. Never use RTK to change permissions, enable repository filters/hooks, authenticate, or bypass a denied command.
      """
    else
      "\n\nRTK: #{mode}. #{reason}"
    end
  end

  def request_policy(request) do
    Enum.find_value(request.plugins, %{}, fn plugin ->
      if plugin["key"] == "rtk" and plugin["kind"] == "shell_filter", do: plugin["policy"]
    end)
  end

  def other_plugins(plugins),
    do: Enum.reject(plugins, &(&1["key"] == "rtk" and &1["kind"] == "shell_filter"))

  def prepare_request(request) do
    case prepare(request) do
      :ok ->
        instruction = instructions(request)

        if String.ends_with?(request.objective, instruction),
          do: request,
          else: %{request | objective: request.objective <> instruction}

      {:error, _reason} ->
        # Failed preparation occurs before execution; do not retry the provider command.
        prepare_request(%{request | plugins: Enum.map(request.plugins, &unavailable/1)})
    end
  end

  defp unavailable(%{"key" => "rtk", "kind" => "shell_filter"} = plugin),
    do: Map.update!(plugin, "policy", &Map.put(&1, "preparation_error", true))

  defp unavailable(plugin), do: plugin

  def prepare(request) do
    policy = request_policy(request)

    if elem(status(policy), 0) == "Instructions only" do
      prepare_storage(request.run_dir, get_in(policy, ["binary", "path"]))
    else
      :ok
    end
  end

  def wrapper(run_dir), do: Path.join([run_dir, "agent", "rtk", "bin", "rtk"])

  defp prepare_storage(run_dir, binary) do
    root = Path.join([run_dir, "agent", "rtk"])

    directories = [
      run_dir,
      Path.join(run_dir, "agent"),
      root,
      Path.join(root, "bin"),
      Path.join(root, "home"),
      Path.join(root, "history-disabled")
    ]

    with :ok <- Enum.reduce_while(directories, :ok, &prepare_directory/2) do
      write_private(wrapper(run_dir), launcher(root, binary), 0o500)
    end
  end

  defp prepare_directory(path, :ok) do
    result =
      case File.lstat(path) do
        {:ok, %{type: :directory}} -> :ok
        {:error, :enoent} -> with :ok <- File.mkdir(path), do: File.chmod(path, 0o700)
        _other -> {:error, :rtk_storage_not_directory}
      end

    if result == :ok, do: {:cont, :ok}, else: {:halt, result}
  end

  defp write_private(path, contents, mode) do
    case File.lstat(path) do
      {:ok, %{type: :regular}} ->
        if File.read!(path) == contents, do: :ok, else: {:error, :rtk_config_changed}

      {:error, :enoent} ->
        with :ok <- File.write(path, contents, [:exclusive]), do: File.chmod(path, mode)

      _other ->
        {:error, :rtk_config_not_regular}
    end
  end

  defp launcher(root, binary) do
    """
    #!/bin/sh
    # App-owned RTK state; no raw recall, persistent command history or repository filters.
    export HOME=#{quote_shell(Path.join(root, "home"))}
    export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
    # RTK 0.49.0 ignores tracking.enabled and pre-creates :memory: as a worktree file.
    # A directory makes its optional SQLite tracker fail closed without storing commands.
    export RTK_DB_PATH=#{quote_shell(Path.join(root, "history-disabled"))}
    export RTK_RECALL=0 RTK_TEE=0 RTK_NO_TOML=1 RTK_HOOK_AUDIT=0 DO_NOT_TRACK=1
    unset RTK_TRUST_PROJECT_FILTERS RTK_TOML_DEBUG
    exec #{quote_shell(binary)} "$@"
    """
  end

  def quote_shell(value), do: "'" <> String.replace(value, "'", "'\"'\"'") <> "'"

  def annotate(metadata) do
    command = metadata["command"] || get_in(metadata, ["input", "command"])

    if is_binary(command) do
      command = reported_shell_body(command)

      observation =
        cond do
          Regex.match?(~r/^\s*(?:rtk|'[^']*\/rtk'|"[^"]*\/rtk"|[^\s'"]*\/rtk)\s+proxy\b/, command) ->
            "raw_output_exception"

          Regex.match?(~r/^\s*(?:rtk|'[^']*\/rtk'|"[^"]*\/rtk"|[^\s'"]*\/rtk)\s+/, command) ->
            "rtk_invocation_reported"

          String.contains?(command, "rtk") ->
            "unknown"

          true ->
            "bypass_reported"
        end

      Map.put(metadata, "rtk", %{
        "observation" => observation,
        "coverage" => "unknown",
        "reduction" => "unknown",
        "source" => "provider_reported"
      })
    else
      metadata
    end
  end

  # Recognize the literal envelope reported by Codex, without parsing or rewriting shell.
  # Quoted/escaped inner commands remain unknown rather than implying verified execution.
  defp reported_shell_body(command) do
    case Regex.run(~r/\A\/(?:usr\/)?bin\/(?:zsh|bash|sh) -l?c '([^']*)'\z/, command) do
      [_, body] -> body
      _other -> command
    end
  end

  def record(run_id, mode, reason, extra \\ %{}) do
    EventStore.append(run_id, %{
      event_type: "rtk.command",
      public_summary: "RTK: #{mode} — #{reason}",
      payload:
        Map.merge(
          %{
            "mode" => mode,
            "reason" => reason,
            "coverage" => "unknown",
            "reduction" => "unknown"
          },
          extra
        )
    })
  end

  def filter_command(run, environment, command, operation, options, execute) do
    plan =
      filter_plan(policy(run, Keyword.get(options, :role_key)), environment, operation, options)

    # Preparation precedes the original command. Filtering never executes it again.
    result = execute.()
    finish_filter(plan, result, run, environment, command)
  end

  defp filter_plan(policy, environment, operation, options) do
    {mode, reason} = status(policy)

    cond do
      mode != "Instructions only" ->
        {:bypass, mode, reason}

      operation == :start ->
        {:bypass, "Bypass", "Streaming output required"}

      Keyword.get(options, :raw_output, false) ->
        {:bypass, "Bypass", "Exact output requested"}

      prepare_storage(environment.run_dir, get_in(policy, ["binary", "path"])) != :ok ->
        {:bypass, "Unavailable", "Isolated filter preparation failed"}

      true ->
        {:filter, policy["binary"]}
    end
  end

  defp finish_filter(
         {:filter, binary},
         {:ok, %{exit_status: 0, truncated?: false} = completed} = result,
         run,
         environment,
         command
       ) do
    case Cuckoding.Plugins.Reference.RTK.filter(
           %{"environment" => environment, "completed" => completed, "binary" => binary},
           %{run_id: run.id}
         ) do
      {:ok, %{data: %{"output" => output}}} ->
        record(run.id, "Automatic", "Captured application output filtered", %{
          "command_role" => command.role,
          "source" => "host_observed"
        })

        {:ok, %{completed | output: output}}

      _passthrough ->
        record(run.id, "Bypass", "Filter unavailable; retained original output")
        result
    end
  end

  defp finish_filter({:filter, _binary}, result, run, _environment, _command) do
    record(run.id, "Bypass", "Failure or incomplete output preserved")
    result
  end

  defp finish_filter({:bypass, mode, reason}, result, run, _environment, _command) do
    record(run.id, mode, reason)
    result
  end

  @doc false
  def filter_output(environment, result, binary) do
    artifact = Path.expand(result.artifact_path)
    root = Path.join(Path.expand(environment.run_dir), "artifacts") <> "/"

    with true <- available?(binary),
         true <- String.starts_with?(artifact, root),
         {:ok, %{type: :regular, size: size}} when size <= 1_048_576 <- File.lstat(artifact),
         true <- available_wrapper?(environment.run_dir, binary["path"]),
         {output, 0} <-
           System.cmd(
             "/usr/bin/ruby",
             [
               "--disable=gems",
               Application.app_dir(:cuckoding, "priv/rtk_filter.rb"),
               wrapper(environment.run_dir),
               artifact
             ],
             cd: environment.worktree_path,
             env:
               Enum.map(System.get_env(), fn {key, _value} -> {key, nil} end) ++
                 [{"PATH", "/usr/bin:/bin:/usr/sbin:/sbin"}],
             stderr_to_stdout: false
           ) do
      {:ok, output}
    else
      _other -> :passthrough
    end
  rescue
    _error -> :passthrough
  end

  defp available_wrapper?(run_dir, binary) do
    path = wrapper(run_dir)

    with {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, contents} <- File.read(path) do
      executable?(path) and contents == launcher(Path.join([run_dir, "agent", "rtk"]), binary)
    else
      _other -> false
    end
  end
end
