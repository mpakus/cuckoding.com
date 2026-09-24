defmodule Cuckoding.Adapters.CursorAgent do
  @moduledoc "Cursor Agent adapter with account-owned profiles and run-owned configuration."
  @behaviour Cuckoding.Adapters.AgentAdapter

  alias Cuckoding.Adapters.SharedProfile
  alias Cuckoding.Adapters.Types
  alias Cuckoding.Identifier
  alias Cuckoding.Security.Redactor

  @supported_version "2026.09.15-d2fe57e"
  @model_list_limit 200
  @unsafe_project_paths [
    ".cursor/cli.json",
    ".cursor/hooks.json",
    ".cursor/mcp.json",
    ".cursor/sandbox.json",
    ".cursor/plugins"
  ]
  @unsafe_profile_paths [
    "home/.cursor/plugins",
    "home/.cursor/hooks.json",
    "config/hooks.json",
    "home/.claude/plugins",
    "config/plugins",
    "claude/plugins"
  ]

  def warning, do: nil

  @impl true
  def probe(options) do
    runner = Keyword.get(options, :command_runner, &System.cmd/3)

    with {:ok, path} <- executable(options),
         {:ok, environment} <- scoped_environment(options),
         {version, 0} <- runner.(path, ["--version"], command_options(environment)),
         :ok <- supported?(String.trim(version)),
         {status, status_code} <-
           runner.(path, ["status", "--format", "json"], command_options(environment)),
         true <- status_code in [0, 1],
         {:ok, %{"isAuthenticated" => authenticated?}} when is_boolean(authenticated?) <-
           Jason.decode(status) do
      verified? = Keyword.get(options, :run_scoped_authenticated?, false)

      {:ok,
       %Types.Probe{
         adapter: "cursor_agent",
         path: path,
         version: @supported_version,
         available?: true,
         authenticated?: authenticated? and verified?,
         status: probe_status(authenticated?, verified?)
       }}
    else
      false -> error(:run_scoped_config_required, :authentication, false)
      {:error, %Types.Error{} = error} -> {:error, error}
      _other -> error(:probe_failed, :provider, true)
    end
  end

  @impl true
  def capabilities(_options) do
    {:ok,
     %Types.Capabilities{
       structured_output?: true,
       native_resume?: true,
       cancellation?: true,
       usage?: true,
       mcp?: false,
       permission_modes: ["plan", "workspace-write"],
       model_discovery?: true,
       instruction_files: ["AGENTS.md", ".cursor/rules"],
       shell_rewrite: Cuckoding.Plugins.RTK.capability("cursor_agent"),
       skill_directories: []
     }}
  end

  def available_models(options) do
    runner = Keyword.get(options, :command_runner, &System.cmd/3)

    with {:ok, path} <- executable(options),
         {:ok, environment} <- scoped_environment(options),
         {output, 0} <- runner.(path, ["models"], command_options(environment)) do
      {:ok, parse_models(output)}
    else
      {:error, %Types.Error{} = error} -> {:error, error}
      _other -> error(:model_discovery_failed, :provider, true)
    end
  end

  @impl true
  def render_config(%Types.StageRequest{} = request, options) do
    request = Cuckoding.Plugins.RTK.prepare_request(request)
    root = Path.join([request.run_dir, "agent", "cursor"])
    home = Path.join(root, "home")
    cursor_home = Path.join(home, ".cursor")
    config = Path.join(root, "config")
    claude = Path.join(root, "claude")

    with :ok <- plugins_disabled(Cuckoding.Plugins.RTK.other_plugins(request.plugins)),
         :ok <- project_overrides_absent(request.worktree_path),
         :ok <- prepare_directory(root, Path.join(request.run_dir, "agent")),
         :ok <- prepare_directory(home, root),
         :ok <- prepare_directory(cursor_home, home),
         :ok <- prepare_directory(config, root),
         :ok <- prepare_directory(claude, root),
         :ok <- profile_plugins_absent(root),
         :ok <- write_file(Path.join(config, "cli-config.json"), cli_config(request)),
         :ok <- write_file(Path.join(cursor_home, "sandbox.json"), sandbox_config()),
         :ok <- write_file(Path.join(cursor_home, "mcp.json"), ~s({"mcpServers":{}})),
         {:ok, _environment} <- scoped_environment(Keyword.put(options, :cursor_home, root)) do
      grant = effective_grant(request)

      grant =
        if options[:shared_profile_id],
          do: %{grant | enforced: Map.put(grant.enforced, "runtime_home", "shared_agent_profile")},
          else: grant

      {:ok, grant}
    else
      {:error, %Types.Error{} = error} -> {:error, error}
      {:error, reason} -> error(reason, :capability, false)
    end
  end

  @impl true
  def start(%Types.StageRequest{} = request, options) do
    with {:ok, grant} <- render_config(request, options),
         {:ok, spec} <- launch_spec(request, options),
         {:ok, process} <- launch(spec, options) do
      {:ok,
       %Types.Session{
         adapter: "cursor_agent",
         session_id: Identifier.generate(),
         external_session_id: Keyword.get(options, :resume_session),
         requested_model: request.requested_model,
         actual_model: nil,
         effective_grant: grant,
         state: "running",
         process: process
       }}
    end
  end

  @impl true
  def send(%Types.Session{}, _input, _options),
    do: error(:follow_up_requires_resume, :capability, false)

  @impl true
  def pause(%Types.Session{} = session, _options) do
    {:ok,
     %{
       "session_id" => session.session_id,
       "external_session_id" => session.external_session_id,
       "summary" => "Cursor Agent session checkpoint"
     }}
  end

  @impl true
  def resume(%Types.Session{external_session_id: external_id}, _checkpoint, options)
      when is_binary(external_id) do
    case Keyword.get(options, :request) do
      %Types.StageRequest{} = request ->
        start(request, Keyword.put(options, :resume_session, external_id))

      _other ->
        error(:request_required, :capability, false)
    end
  end

  def resume(%Types.Session{}, _checkpoint, _options),
    do: error(:session_id_required, :capability, false)

  def resume(%Types.ContinuationPackage{} = package, _checkpoint, options) do
    case Keyword.get(options, :request) do
      %Types.StageRequest{} = request ->
        start(request, Keyword.put(options, :prompt, continuation_prompt(package)))

      _other ->
        error(:request_required, :capability, false)
    end
  end

  @impl true
  def recover(%Types.Session{} = session, inspection, options) when is_map(inspection) do
    if inspection[:process] == :matching and inspection[:session] == :available,
      do: {:ok, session},
      else: resume(session, %{"reason" => "sleep_gap"}, options)
  end

  @impl true
  def cancel(%Types.Session{process: %{runner: runner, handle: handle}} = session, _options) do
    case runner.stop(handle) do
      {:ok, _result} -> {:ok, %{session | state: "cancelled"}}
      {:error, reason} -> error(reason, :provider, false)
    end
  end

  def cancel(%Types.Session{}, _options), do: error(:process_unavailable, :provider, false)

  @impl true
  def inspect(%Types.Session{} = session, _options), do: {:ok, Map.from_struct(session)}

  @impl true
  def decode_event(provider_event, options) when is_map(provider_event) do
    with {:ok, type} <- event_type(provider_event),
         {:ok, sequence} <- event_sequence(options) do
      redact = Keyword.get(options, :redact, [])

      {:ok,
       %Types.Event{
         event_id: event_id(provider_event, sequence),
         sequence: sequence,
         type: type,
         public_summary: provider_event |> summary(type) |> Redactor.redact(redact),
         metadata: provider_event |> metadata(type) |> Redactor.redact(redact),
         trust: :untrusted
       }}
    end
  end

  def decode_event(_provider_event, _options),
    do: error(:malformed_event, :malformed_output, false)

  @impl true
  def collect_usage(%Types.Session{}, options) do
    case Keyword.get(options, :usage) do
      nil ->
        {:ok, Types.Usage.unavailable()}

      usage when is_map(usage) ->
        {:ok,
         %Types.Usage{
           source: "provider",
           confidence: "reported",
           input_tokens: usage["inputTokens"],
           output_tokens: usage["outputTokens"],
           reasoning_tokens: nil,
           cache_read_tokens: usage["cacheReadTokens"],
           cache_write_tokens: usage["cacheWriteTokens"],
           cost_micros: nil,
           currency: nil
         }}

      _other ->
        error(:malformed_usage, :malformed_output, false)
    end
  end

  def launch_spec(%Types.StageRequest{} = request, options \\ []) do
    request = Cuckoding.Plugins.RTK.prepare_request(request)

    with {:ok, path} <- executable(options),
         true <- Keyword.get(options, :run_scoped_authenticated?, false),
         :ok <- valid_model(request.requested_model),
         :ok <- valid_resume_session(options),
         :ok <- project_overrides_absent(request.worktree_path),
         :ok <- config_ready(request),
         {:ok, environment} <-
           scoped_environment(Keyword.put(options, :cursor_home, cursor_root(request))),
         {:ok, timeout} <- wall_timeout(request.grant) do
      args =
        [
          "--print",
          "--output-format",
          "stream-json",
          "--sandbox",
          "enabled",
          "--trust",
          "--workspace",
          request.worktree_path
        ]
        |> maybe_arg("--mode", execution_mode(request.grant))
        |> maybe_arg("--model", request.requested_model)
        |> maybe_arg("--resume", Keyword.get(options, :resume_session))
        |> Kernel.++([Keyword.get(options, :prompt, request.objective)])

      {:ok,
       %{
         command: %{executable: path, args: args, role: "agent:cursor_agent"},
         environment: environment,
         environment_allowlist: Map.keys(environment),
         timeout: timeout
       }}
    else
      false -> error(:run_scoped_auth_required, :authentication, false)
      {:error, %Types.Error{} = error} -> {:error, error}
      {:error, reason} -> error(reason, :capability, false)
    end
  end

  defp launch(spec, options) do
    runner = Keyword.get(options, :runner)
    environment = Keyword.get(options, :environment)

    if runner && environment do
      case runner.start(environment, spec.command,
             env: spec.environment,
             environment_allowlist: spec.environment_allowlist,
             timeout: spec.timeout,
             redact: Keyword.get(options, :redact, [])
           ) do
        {:ok, handle} -> {:ok, %{runner: runner, handle: handle, launch: spec}}
        {:error, reason} -> error(reason, :provider, true)
      end
    else
      error(:runner_required, :capability, false)
    end
  end

  defp executable(options) do
    case Keyword.get(options, :path) || System.find_executable("cursor-agent") ||
           System.find_executable("agent") do
      path when is_binary(path) -> {:ok, Path.expand(path)}
      _other -> error(:not_installed, :availability, false)
    end
  end

  defp supported?(@supported_version), do: :ok
  defp supported?(_version), do: error(:unsupported_version, :availability, false)

  defp scoped_environment(options) when is_list(options) do
    case Keyword.get(options, :cursor_home) do
      path when is_binary(path) ->
        with {:ok, environment} <- scoped_environment(path),
             do: shared_environment(environment, options[:shared_profile_id])

      _other ->
        error(:run_scoped_config_required, :authentication, false)
    end
  end

  defp scoped_environment(root) when is_binary(root) do
    root = Path.expand(root)

    {:ok,
     %{
       "AGENT_CLI_CREDENTIAL_STORE" => "file",
       "HOME" => Path.join(root, "home"),
       "CURSOR_CONFIG_DIR" => Path.join(root, "config"),
       "CLAUDE_CONFIG_DIR" => Path.join(root, "claude")
     }}
  end

  defp shared_environment(environment, nil), do: {:ok, environment}

  defp shared_environment(environment, id) do
    with {:ok, root} <- SharedProfile.prepare(id, "cursor_agent"),
         {:ok, shared} <- account_environment(root),
         do: {:ok, Map.put(environment, "HOME", shared["HOME"])}
  end

  def account_environment(root) do
    with :ok <- prepare_directory(Path.join(root, "home"), root),
         :ok <- prepare_directory(Path.join(root, "config"), root),
         :ok <- prepare_directory(Path.join(root, "claude"), root),
         :ok <- prepare_directory(Path.join(root, "home/.cursor"), Path.join(root, "home")),
         :ok <- profile_plugins_absent(root),
         :ok <- fixed_file(Path.join(root, "home/.cursor/sandbox.json"), sandbox_config()),
         :ok <- fixed_file(Path.join(root, "home/.cursor/mcp.json"), ~s({"mcpServers":{}})) do
      scoped_environment(root)
    end
  end

  # Shared security files are constant, never overwritten with another run's policy.
  defp fixed_file(path, contents) do
    case File.lstat(path) do
      {:error, :enoent} ->
        case File.write(path, contents, [:exclusive]) do
          :ok -> File.chmod(path, 0o600)
          {:error, :eexist} -> fixed_file(path, contents)
          error -> error
        end

      {:ok, %{type: :regular}} ->
        if File.read(path) == {:ok, contents},
          do: :ok,
          else: {:error, :shared_profile_configuration_changed}

      _other ->
        {:error, :config_path_symlink}
    end
  end

  defp cursor_root(request), do: Path.join([request.run_dir, "agent", "cursor"])

  defp command_options(environment),
    do: [stderr_to_stdout: true, env: Enum.to_list(environment)]

  defp parse_models(output) do
    output
    |> String.replace(~r/\e\[[0-9;]*m/, "")
    |> String.split("\n", trim: true)
    |> Enum.reduce([], fn line, models ->
      line = String.trim(line)

      line =
        Regex.replace(
          ~r/\s+\((?:current|default)(?:,\s*(?:current|default))*\)\z/,
          line,
          ""
        )

      case String.split(line, " - ", parts: 2) do
        [id, label] -> maybe_model(models, id, label)
        [id] -> maybe_model(models, id, id)
      end
    end)
    |> Enum.reverse()
    |> Enum.uniq_by(& &1["id"])
    |> Enum.take(@model_list_limit)
  end

  defp maybe_model(models, id, label) do
    id = String.trim(id)
    label = String.trim(label)

    if byte_size(id) <= 128 and label != "" and byte_size(label) <= 120 and
         String.printable?(label) and
         Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.:\/-]*\z/, id),
       do: [%{"id" => id, "label" => label} | models],
       else: models
  end

  defp probe_status(true, true), do: "healthy"
  defp probe_status(true, false), do: "run_scoped_auth_unverified"
  defp probe_status(false, _verified), do: "authentication_required"

  defp project_overrides_absent(worktree) do
    case Enum.find(@unsafe_project_paths, &File.exists?(Path.join(worktree, &1))) do
      nil -> :ok
      path -> {:error, {:project_cursor_configuration_unsupported, path}}
    end
  end

  defp profile_plugins_absent(root) do
    case Enum.find(@unsafe_profile_paths, &File.exists?(Path.join(root, &1))) do
      nil -> :ok
      path -> {:error, {:run_cursor_plugins_unsupported, path}}
    end
  end

  defp cli_config(request) do
    tools =
      if execution_mode(request.grant) == "plan",
        do: ["read"],
        else: Map.get(request.grant, "tools", [])

    allow =
      tools
      |> Enum.flat_map(&permission/1)
      |> Enum.uniq()

    Jason.encode!(%{
      "version" => 1,
      "editor" => %{"vimMode" => false},
      "permissions" => %{
        "allow" => allow,
        "deny" => [
          "Mcp(*:*)",
          "WebFetch(*)",
          "Read(.env*)",
          "Read(**/*.key)",
          "Write(.env*)",
          "Write(**/*.key)"
        ]
      },
      "sandbox" => %{"mode" => "enabled", "networkAccess" => "deny"},
      "attribution" => %{
        "attributeCommitsToAgent" => false,
        "attributePRsToAgent" => false
      }
    })
  end

  defp permission("read"), do: ["Read(**/*)"]
  defp permission("write"), do: ["Write(**/*)"]
  defp permission("shell"), do: ["Shell(*)"]
  defp permission(_tool), do: []

  defp sandbox_config do
    Jason.encode!(%{
      "type" => "workspace_readwrite",
      "additionalReadwritePaths" => [],
      "additionalReadonlyPaths" => [],
      "networkPolicy" => %{"default" => "deny", "allow" => [], "deny" => []}
    })
  end

  defp effective_grant(request) do
    enforced = %{
      "runtime_home" => "run_owned",
      "runtime_sandbox_active" => true,
      "mode" => execution_mode(request.grant) || "workspace-write",
      "paths" => [request.worktree_path],
      "network" => "deny",
      "mcp" => "disabled",
      "plugins" => "disabled"
    }

    unenforced =
      request.grant
      |> Map.take(["deny_tools", "resource_limits"])
      |> Map.put(
        "additional_paths",
        Map.get(request.grant, "paths", []) -- [request.worktree_path]
      )

    %Types.EffectiveGrant{requested: request.grant, enforced: enforced, unenforced: unenforced}
  end

  defp execution_mode(%{"approval_mode" => "plan"}), do: "plan"
  defp execution_mode(_grant), do: nil

  defp valid_model(nil), do: :ok

  defp valid_model(model) when is_binary(model) do
    if Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9._:\-\[\]=,]*\z/, model),
      do: :ok,
      else: {:error, :invalid_model}
  end

  defp valid_model(_model), do: {:error, :invalid_model}

  defp valid_resume_session(options) do
    case Keyword.get(options, :resume_session) do
      nil ->
        :ok

      id when is_binary(id) ->
        if Regex.match?(~r/\A[a-zA-Z0-9_-]{1,128}\z/, id),
          do: :ok,
          else: {:error, :invalid_session_id}

      _other ->
        {:error, :invalid_session_id}
    end
  end

  defp wall_timeout(grant) do
    case get_in(grant, ["resource_limits", "wall_ms"]) do
      timeout when is_integer(timeout) and timeout > 0 and timeout <= 86_400_000 -> {:ok, timeout}
      _other -> {:error, :invalid_wall_time_limit}
    end
  end

  defp plugins_disabled([]), do: :ok
  defp plugins_disabled(_plugins), do: {:error, :plugins_unsupported}

  defp config_ready(request) do
    root = cursor_root(request)

    files = [
      Path.join(root, "config/cli-config.json"),
      Path.join(root, "home/.cursor/sandbox.json"),
      Path.join(root, "home/.cursor/mcp.json")
    ]

    if Enum.all?(files, &File.regular?/1),
      do: :ok,
      else: {:error, :config_missing}
  end

  defp prepare_directory(path, parent) do
    if Path.dirname(Path.expand(path)) == Path.expand(parent) do
      case File.lstat(path) do
        {:ok, %{type: :directory}} -> File.chmod(path, 0o700)
        {:ok, %{type: :symlink}} -> {:error, :config_path_symlink}
        {:ok, _other} -> {:error, :config_path_not_directory}
        {:error, :enoent} -> create_directory(path)
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :config_path_escape}
    end
  end

  defp create_directory(path) do
    with :ok <- File.mkdir(path), do: File.chmod(path, 0o700)
  end

  defp write_file(path, contents) do
    with {:ok, file} <- File.open(path, [:write, :exclusive, :binary]),
         :ok <- IO.binwrite(file, contents),
         :ok <- File.close(file),
         :ok <- File.chmod(path, 0o600) do
      :ok
    else
      {:error, :eexist} -> replace_file(path, contents)
      {:error, reason} -> {:error, reason}
    end
  end

  defp replace_file(path, contents) do
    case File.lstat(path) do
      {:ok, %{type: :regular}} ->
        with :ok <- File.write(path, contents), do: File.chmod(path, 0o600)

      {:ok, _other} ->
        {:error, :config_path_symlink}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp event_type(%{"type" => "system", "subtype" => "init"}), do: {:ok, "session.started"}

  defp event_type(%{"type" => "tool_call", "subtype" => "started"}),
    do: {:ok, "tool.requested"}

  defp event_type(%{"type" => "tool_call", "subtype" => "completed"}),
    do: {:ok, "tool.completed"}

  defp event_type(%{"type" => "result", "subtype" => "success"}),
    do: {:ok, "session.completed"}

  defp event_type(%{"type" => "result", "subtype" => "error"}),
    do: {:ok, "session.failed"}

  defp event_type(%{"type" => _type}), do: error(:unknown_event, :malformed_output, false)
  defp event_type(_event), do: error(:malformed_event, :malformed_output, false)

  defp event_sequence(options) do
    case Keyword.get(options, :sequence, 0) do
      sequence when is_integer(sequence) and sequence >= 0 -> {:ok, sequence}
      _other -> error(:malformed_event, :malformed_output, false)
    end
  end

  defp event_id(event, sequence),
    do: event["call_id"] || "cursor:#{event["type"]}:#{event["subtype"]}:#{sequence}"

  defp summary(_event, "session.started"), do: "Cursor Agent session started"
  defp summary(_event, "tool.requested"), do: "Cursor Agent requested a tool"
  defp summary(_event, "tool.completed"), do: "Cursor Agent completed a tool"
  defp summary(event, "session.completed"), do: event["result"] || "Cursor Agent completed"
  defp summary(event, "session.failed"), do: event["result"] || "Cursor Agent failed"

  defp metadata(event, "session.started"),
    do: Map.take(event, ["session_id", "model", "permissionMode"])

  defp metadata(event, type) when type in ["tool.requested", "tool.completed"] do
    metadata = Map.take(event, ["call_id", "session_id"])

    case get_in(event, ["tool_call", "shellToolCall", "args", "command"]) do
      command when is_binary(command) ->
        Map.merge(
          metadata,
          Map.take(Cuckoding.Plugins.RTK.annotate(%{"command" => command}), ["rtk"])
        )

      _other ->
        metadata
    end
  end

  defp metadata(event, type) when type in ["session.completed", "session.failed"],
    do: Map.take(event, ["session_id", "request_id", "duration_ms", "usage", "is_error"])

  defp maybe_arg(args, _flag, value) when value in [nil, ""], do: args
  defp maybe_arg(args, flag, value), do: args ++ [flag, to_string(value)]

  defp continuation_prompt(package) do
    "Continue task revision #{package.task_revision}.\n\n#{package.summary}\n\nDiff: #{package.diff_summary}"
  end

  defp error(code, category, retryable?),
    do: {:error, Types.Error.new(code, category, retryable?)}
end
