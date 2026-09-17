defmodule Cuckoding.Adapters.ClaudeCode do
  @moduledoc "Claude Code 2.1.142 adapter with run-scoped configuration and host-runner launch specs."
  @behaviour Cuckoding.Adapters.AgentAdapter

  alias Cuckoding.Adapters.Types
  alias Cuckoding.Identifier
  alias Cuckoding.Security.Redactor

  @supported_version "2.1.142"
  @event_types %{
    {"system", "init"} => "session.started",
    {"system", "api_retry"} => "rate_limited",
    {"result", "success"} => "session.completed",
    {"result", "error"} => "session.failed"
  }

  @impl true
  def probe(options) do
    runner = Keyword.get(options, :command_runner, &System.cmd/3)

    with {:ok, path} <- executable(options),
         {version_output, 0} <- runner.(path, ["--version"], stderr_to_stdout: true),
         {:ok, version} <- parse_version(version_output),
         :ok <- supported?(version),
         {:ok, auth} <- auth_status(path, runner) do
      helper? = valid_helper?(Keyword.get(options, :api_key_helper))
      scoped_auth? = helper? and Keyword.get(options, :run_scoped_authenticated?, false)

      {:ok,
       %Types.Probe{
         adapter: "claude_code",
         path: path,
         version: version,
         available?: true,
         authenticated?: scoped_auth?,
         status: probe_status(auth, helper?, scoped_auth?)
       }}
    else
      {:error, %Types.Error{} = error} -> {:error, error}
      {_output, _status} -> error(:probe_failed, :provider, true)
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
       mcp?: true,
       permission_modes: ["dontAsk", "plan"],
       model_discovery?: false,
       instruction_files: ["instructions.md"],
       skill_directories: ["claude-plugin/skills"]
     }}
  end

  @impl true
  def render_config(%Types.StageRequest{} = request, options) do
    root = Path.join(request.run_dir, "agent")
    claude_dir = Path.join(root, "claude")
    plugin_dir = Path.join(root, "claude-plugin")
    grant = effective_grant(request.grant)

    settings =
      %{
        "permissions" => %{
          "defaultMode" => permission_mode(request.grant),
          "allow" => Map.get(request.grant, "tools", []),
          "deny" => Map.get(request.grant, "deny_tools", [])
        },
        "autoMemoryEnabled" => false,
        "disableAllHooks" => true,
        "enabledPlugins" => %{}
      }
      |> maybe_api_key_helper(Keyword.get(options, :api_key_helper))

    with :ok <- prepare_directory(root, request.run_dir),
         :ok <- prepare_directory(claude_dir, root),
         :ok <- prepare_directory(plugin_dir, root),
         :ok <- write_file(Path.join(claude_dir, "settings.json"), Jason.encode!(settings)),
         :ok <- write_file(Path.join(claude_dir, "mcp.json"), Jason.encode!(mcp_config(request))),
         :ok <- write_file(Path.join(claude_dir, "instructions.md"), instructions(request)),
         :ok <- write_skills(plugin_dir, request.plugins) do
      {:ok, grant}
    else
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
         adapter: "claude_code",
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
       "summary" => "Claude Code session checkpoint"
     }}
  end

  @impl true
  def resume(%Types.Session{} = session, _checkpoint, options) do
    case Keyword.get(options, :request) do
      %Types.StageRequest{} = request ->
        start(request, Keyword.put(options, :resume_session, session.external_session_id))

      _other ->
        error(:request_required, :capability, false)
    end
  end

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
    redact = Keyword.get(options, :redact, [])

    with {:ok, type} <- event_type(provider_event),
         {:ok, event_id} <- event_id(provider_event),
         {:ok, sequence} <- event_sequence(provider_event, options) do
      {:ok,
       %Types.Event{
         event_id: event_id,
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
      nil -> {:ok, Types.Usage.unavailable()}
      usage when is_map(usage) -> usage(usage)
      _other -> error(:malformed_usage, :malformed_output, false)
    end
  end

  def knowledge_citations(
        %{"structured_output" => %{"knowledge_citations" => citations}},
        options
      )
      when is_list(citations) do
    redact = Keyword.get(options, :redact, [])
    sequence = Keyword.get(options, :sequence, 0)

    citations
    |> Enum.with_index()
    |> Enum.map(fn {citation, offset} ->
      %Types.Event{
        event_id: "knowledge:#{Map.get(citation, "id", offset)}",
        sequence: sequence + offset,
        type: "knowledge.cited",
        public_summary: "Claude Code cited reviewed project knowledge",
        metadata: Redactor.redact(citation, redact),
        trust: :untrusted
      }
    end)
  end

  def knowledge_citations(_provider_event, _options), do: []

  def launch_spec(%Types.StageRequest{} = request, options \\ []) do
    with {:ok, path} <- executable(options),
         true <- valid_helper?(Keyword.get(options, :api_key_helper)) do
      claude_dir = Path.join([request.run_dir, "agent", "claude"])
      plugin_dir = Path.join([request.run_dir, "agent", "claude-plugin"])

      args =
        [
          "--bare",
          "--print",
          "--output-format",
          "stream-json",
          "--verbose",
          "--permission-mode",
          permission_mode(request.grant),
          "--allowedTools",
          Enum.join(Map.get(request.grant, "tools", []), ","),
          "--disallowedTools",
          Enum.join(Map.get(request.grant, "deny_tools", []), ","),
          "--settings",
          Path.join(claude_dir, "settings.json"),
          "--strict-mcp-config",
          "--mcp-config",
          Path.join(claude_dir, "mcp.json"),
          "--plugin-dir",
          plugin_dir,
          "--append-system-prompt-file",
          Path.join(claude_dir, "instructions.md"),
          "--no-chrome"
        ]
        |> maybe_arg("--model", request.requested_model)
        |> maybe_arg("--json-schema", schema(request.required_output_schema))
        |> maybe_arg("--max-budget-usd", Map.get(request.grant, "max_budget_usd"))
        |> maybe_arg("--resume", Keyword.get(options, :resume_session))
        |> Kernel.++([Keyword.get(options, :prompt, request.objective)])

      {:ok,
       %{
         command: %{executable: path, args: args, role: "agent:claude_code"},
         environment: %{
           "CLAUDE_CONFIG_DIR" => claude_dir,
           "CLAUDE_CODE_DISABLE_AUTO_MEMORY" => "1",
           "CLAUDE_CODE_DISABLE_BACKGROUND_TASKS" => "1"
         },
         environment_allowlist: [
           "CLAUDE_CONFIG_DIR",
           "CLAUDE_CODE_DISABLE_AUTO_MEMORY",
           "CLAUDE_CODE_DISABLE_BACKGROUND_TASKS"
         ]
       }}
    else
      false -> error(:run_scoped_auth_required, :authentication, false)
      {:error, reason} -> {:error, reason}
    end
  end

  defp launch(spec, options) do
    runner = Keyword.get(options, :runner)
    environment = Keyword.get(options, :environment)

    if runner && environment do
      case runner.start(environment, spec.command,
             env: spec.environment,
             environment_allowlist: spec.environment_allowlist,
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
    case Keyword.get(options, :path) || System.find_executable("claude") do
      path when is_binary(path) -> {:ok, Path.expand(path)}
      _other -> error(:not_installed, :availability, false)
    end
  end

  defp parse_version(output) do
    case Regex.run(~r/^(\d+\.\d+\.\d+)/, String.trim(output), capture: :all_but_first) do
      [version] -> {:ok, version}
      _other -> error(:invalid_version, :malformed_output, false)
    end
  end

  defp supported?(@supported_version), do: :ok
  defp supported?(_version), do: error(:unsupported_version, :availability, false)

  defp auth_status(path, runner) do
    case runner.(path, ["auth", "status", "--json"], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"loggedIn" => logged_in, "authMethod" => method}} ->
            {:ok, %{logged_in?: logged_in, method: method}}

          _other ->
            error(:malformed_auth_status, :malformed_output, false)
        end

      {_output, _status} ->
        error(:auth_probe_failed, :authentication, true)
    end
  end

  defp probe_status(_auth, true, true), do: "healthy"
  defp probe_status(_auth, true, false), do: "run_scoped_auth_unverified"
  defp probe_status(%{logged_in?: true}, false, false), do: "run_scoped_auth_required"
  defp probe_status(_auth, false, false), do: "authentication_required"

  defp valid_helper?(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} ->
        Path.type(path) == :absolute and Bitwise.band(mode, 0o111) != 0

      _other ->
        false
    end
  end

  defp valid_helper?(_path), do: false

  defp maybe_api_key_helper(settings, path) do
    if valid_helper?(path), do: Map.put(settings, "apiKeyHelper", path), else: settings
  end

  defp effective_grant(requested) do
    enforced = Map.take(requested, ["tools", "deny_tools", "approval_mode", "plugins"])
    unenforced = Map.take(requested, ["paths", "network", "resource_limits"])
    %Types.EffectiveGrant{requested: requested, enforced: enforced, unenforced: unenforced}
  end

  defp permission_mode(grant) do
    if Map.get(grant, "approval_mode") == "plan", do: "plan", else: "dontAsk"
  end

  defp mcp_config(request) do
    servers =
      request.plugins
      |> Enum.filter(&(Map.get(&1, "kind") == "mcp"))
      |> Map.new(&{Map.fetch!(&1, "id"), Map.get(&1, "config", %{})})

    %{"mcpServers" => servers}
  end

  defp instructions(request) do
    knowledge =
      Enum.map_join(
        request.knowledge,
        "\n",
        &"- #{Map.get(&1, "id", "unknown")}: #{Map.get(&1, "content", "")}"
      )

    "# Objective\n\n#{request.objective}\n\n# Reviewed project knowledge\n\n#{knowledge}\n"
  end

  defp write_skills(plugin_dir, plugins) do
    skills_dir = Path.join(plugin_dir, "skills")

    with :ok <- prepare_directory(skills_dir, plugin_dir) do
      plugins
      |> Enum.filter(&(Map.get(&1, "kind") == "instruction"))
      |> Enum.reduce_while(:ok, &write_next_skill(&1, &2, skills_dir))
    end
  end

  defp write_next_skill(plugin, :ok, skills_dir) do
    case write_skill(plugin, skills_dir) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp write_skill(plugin, skills_dir) do
    id = Map.get(plugin, "id", "")

    if Regex.match?(~r/\A[a-z0-9][a-z0-9_-]*\z/, id) do
      directory = Path.join(skills_dir, id)

      with :ok <- prepare_directory(directory, skills_dir) do
        write_file(Path.join(directory, "SKILL.md"), Map.get(plugin, "instructions", ""))
      end
    else
      {:error, :invalid_skill_id}
    end
  end

  defp prepare_directory(path, parent) do
    if Path.dirname(Path.expand(path)) == Path.expand(parent) do
      case File.lstat(path) do
        {:ok, %{type: :directory}} -> :ok
        {:ok, %{type: :symlink}} -> {:error, :config_path_symlink}
        {:ok, _other} -> {:error, :config_path_not_directory}
        {:error, :enoent} -> File.mkdir(path)
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :config_path_escape}
    end
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

  defp maybe_arg(args, _flag, value) when value in [nil, "", %{}], do: args
  defp maybe_arg(args, flag, value), do: args ++ [flag, to_string(value)]
  defp schema(value) when value == %{}, do: nil
  defp schema(value), do: Jason.encode!(value)

  defp continuation_prompt(package) do
    "Continue task revision #{package.task_revision}.\n\n#{package.summary}\n\nDiff: #{package.diff_summary}"
  end

  defp event_type(%{"type" => type, "subtype" => subtype} = event) do
    result_subtype = if type == "result" and event["is_error"], do: "error", else: subtype

    case Map.get(@event_types, {type, result_subtype}) do
      nil -> error(:unknown_event, :malformed_output, false)
      normalized -> {:ok, normalized}
    end
  end

  defp event_type(%{"type" => "assistant", "message" => %{"content" => content}})
       when is_list(content) do
    cond do
      Enum.any?(content, &(Map.get(&1, "type") == "tool_use")) -> {:ok, "tool.requested"}
      Enum.any?(content, &(Map.get(&1, "type") == "text")) -> {:ok, "activity.summary"}
      true -> error(:unknown_event, :malformed_output, false)
    end
  end

  defp event_type(%{"type" => "user", "message" => %{"content" => content}})
       when is_list(content) do
    if Enum.any?(content, &(Map.get(&1, "type") == "tool_result")),
      do: {:ok, "tool.completed"},
      else: error(:unknown_event, :malformed_output, false)
  end

  defp event_type(_event), do: error(:malformed_event, :malformed_output, false)

  defp event_id(event) do
    case event["uuid"] || event["request_id"] || get_in(event, ["message", "id"]) ||
           event["session_id"] do
      value when is_binary(value) -> {:ok, value}
      _other -> error(:malformed_event, :malformed_output, false)
    end
  end

  defp event_sequence(_event, options) do
    case Keyword.get(options, :sequence, 0) do
      sequence when is_integer(sequence) and sequence >= 0 -> {:ok, sequence}
      _other -> error(:malformed_event, :malformed_output, false)
    end
  end

  defp summary(event, "session.started"),
    do: "Claude Code session started with #{event["model"] || "unreported model"}"

  defp summary(event, "session.completed"), do: event["result"] || "Claude Code session completed"

  defp summary(event, "session.failed"),
    do: event["result"] || event["error"] || "Claude Code session failed"

  defp summary(_event, "rate_limited"), do: "Claude Code provider retry scheduled"
  defp summary(event, "activity.summary"), do: text_block(event) || "Claude Code activity"

  defp summary(event, "tool.requested") do
    case content_block(event, "tool_use") do
      %{"name" => name} -> "Claude Code requested #{name}"
      _other -> "Claude Code requested a tool"
    end
  end

  defp summary(_event, "tool.completed"), do: "Claude Code completed a tool call"

  defp metadata(event, "session.started") do
    Map.take(event, ["session_id", "model", "permissionMode", "tools", "mcp_servers", "plugins"])
  end

  defp metadata(event, type) when type in ["session.completed", "session.failed"] do
    Map.take(event, [
      "session_id",
      "request_id",
      "duration_ms",
      "total_cost_usd",
      "usage",
      "structured_output"
    ])
  end

  defp metadata(event, "rate_limited") do
    Map.take(event, [
      "attempt",
      "max_retries",
      "retry_delay_ms",
      "error_status",
      "error",
      "session_id"
    ])
  end

  defp metadata(event, "activity.summary"), do: Map.take(event, ["session_id"])

  defp metadata(event, "tool.requested") do
    event |> content_block("tool_use") |> Map.take(["id", "name", "input"])
  end

  defp metadata(event, "tool.completed") do
    event |> content_block("tool_result") |> Map.take(["tool_use_id", "is_error", "content"])
  end

  defp text_block(event) do
    case content_block(event, "text") do
      %{"text" => text} when is_binary(text) -> text
      _other -> nil
    end
  end

  defp content_block(event, type) do
    event
    |> get_in(["message", "content"])
    |> Enum.find(%{}, &(Map.get(&1, "type") == type))
  end

  defp usage(usage) do
    {:ok,
     %Types.Usage{
       source: "provider",
       confidence: "reported",
       input_tokens: usage["input_tokens"] || usage["inputTokens"],
       output_tokens: usage["output_tokens"] || usage["outputTokens"],
       cache_read_tokens: usage["cache_read_input_tokens"] || usage["cacheReadTokens"],
       cache_write_tokens: usage["cache_creation_input_tokens"] || usage["cacheWriteTokens"],
       cost_micros: dollars_to_micros(usage["total_cost_usd"]),
       currency: if(usage["total_cost_usd"], do: "USD")
     }}
  end

  defp dollars_to_micros(nil), do: nil
  defp dollars_to_micros(value) when is_number(value), do: round(value * 1_000_000)
  defp dollars_to_micros(_value), do: nil

  defp error(code, category, retryable?),
    do: {:error, Types.Error.new(code, category, retryable?)}
end
