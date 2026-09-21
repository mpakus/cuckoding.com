defmodule Cuckoding.AgentRuntime do
  @moduledoc "Resolves one snapshotted role to its isolated provider runtime."

  alias Cuckoding.Adapters
  alias Cuckoding.Adapters.ClaudeCode
  alias Cuckoding.Adapters.Codex
  alias Cuckoding.Adapters.CursorAgent
  alias Cuckoding.Adapters.FakeAdapter
  alias Cuckoding.Adapters.ProviderAccount
  alias Cuckoding.Adapters.SharedProfile

  def resolve(skeleton, role_key) when is_binary(role_key) do
    with {:ok, role} <- role(skeleton, role_key),
         {:ok, adapter, options, version} <- adapter(skeleton, role) do
      {:ok,
       %{
         adapter: adapter,
         options: options,
         version: version,
         settings: role.settings_json,
         requested_model: role.model_ref,
         role_key: role.role_key
       }}
    end
  end

  def resolve_roles(skeleton, roles) do
    Enum.reduce_while(roles, {:ok, %{}, %{}}, fn role, {:ok, resolved, checked} ->
      case cached_runtime(skeleton, role.role_key, checked) do
        {:ok, runtime, key} ->
          {:cont,
           {:ok, Map.put(resolved, role.role_key, runtime), Map.put(checked, key, runtime)}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, resolved, _checked} -> {:ok, resolved}
      error -> error
    end
  end

  defp cached_runtime(skeleton, role_key, checked) do
    with {:ok, assignment} <- role(skeleton, role_key),
         settings = assignment.settings_json,
         {:ok, identity} <- authorization_identity(assignment),
         key =
           {assignment.adapter_key, identity, settings["executable_path"],
            settings["api_key_helper"]},
         {:ok, runtime} <-
           if(Map.has_key?(checked, key),
             do: {:ok, checked[key]},
             else: resolve(skeleton, role_key)
           ) do
      {:ok,
       %{runtime | role_key: role_key, settings: settings, requested_model: assignment.model_ref},
       key}
    end
  end

  def setup(skeleton, role_key) when is_binary(role_key) do
    with {:ok, role} <- role(skeleton, role_key),
         {:ok, setup} <- runtime_setup(skeleton, role) do
      {:ok,
       setup
       |> Map.put(:role_key, role_key)
       |> Map.put(:adapter_key, role.adapter_key)
       |> Map.put(:settings, role.settings_json)
       |> Map.put(:account_id, role.settings_json["provider_account_id"])}
    end
  end

  def account_setup(%ProviderAccount{} = account) do
    with {:ok, root} <- Adapters.authorization_account(account),
         {:ok, setup} <- authorization_setup(root) do
      {:ok, Map.put(setup, :authorization_id, root.id)}
    end
  end

  defp authorization_setup(%ProviderAccount{adapter_key: "codex"} = account) do
    executable = get_in(account.capabilities_json, ["settings", "executable_path"])

    with true <- is_binary(executable) and executable != "",
         {:ok, home} <- SharedProfile.prepare(account.id, "codex") do
      {:ok,
       %{
         runtime: "Codex",
         connection: account.label,
         executable: executable,
         home: home,
         command:
           login_command(%{"CODEX_HOME" => home}, executable, [
             "-c",
             ~s(cli_auth_credentials_store="file"),
             "login",
             "--device-auth"
           ]),
         reusable?: true,
         status: account.status
       }}
    else
      false -> {:error, :runtime_executable_missing}
      error -> error
    end
  end

  defp authorization_setup(%ProviderAccount{adapter_key: "cursor_agent"} = account) do
    executable = get_in(account.capabilities_json, ["settings", "executable_path"])

    with true <- is_binary(executable) and executable != "",
         {:ok, root} <- SharedProfile.prepare(account.id, "cursor_agent"),
         {:ok, environment} <- CursorAgent.account_environment(root) do
      {:ok,
       %{
         runtime: "Cursor Agent",
         connection: account.label,
         executable: executable,
         home: root,
         command: login_command(environment, executable, ["login"]),
         reusable?: true,
         status: account.status
       }}
    else
      false -> {:error, :runtime_executable_missing}
      error -> error
    end
  end

  defp authorization_setup(%ProviderAccount{} = account) do
    {:ok,
     %{
       runtime: runtime_name(account.adapter_key),
       connection: account.label,
       reusable?: account.auth_mode == "api_key_helper",
       status: account.status
     }}
  end

  def check_account(%ProviderAccount{} = account) do
    with %ProviderAccount{} = current <- Adapters.get_provider_account(account.id),
         {:ok, root} <- Adapters.authorization_account(current) do
      case check_authorization(root) do
        {:ok, _checked} ->
          {:ok, Adapters.get_provider_account(account.id)}

        {:error, reason} = error ->
          _recorded =
            Adapters.record_provider_failure(
              root.id,
              :authorization_check,
              reason,
              root.capabilities_json
            )

          error
      end
    else
      nil -> {:error, :provider_account_not_found}
      error -> error
    end
  end

  def disconnect_account(%ProviderAccount{} = account, options \\ []) do
    runner = Keyword.get(options, :command_runner, &System.cmd/3)

    with {:ok, root} <- Adapters.authorization_account(account) do
      disconnect_root(root, runner)
    end
  end

  defp disconnect_root(root, runner) do
    result =
      with {:ok, setup} <- account_setup(root),
           {:ok, _event} <- Adapters.record_provider_disconnect_requested(root.id),
           :ok <- disconnect_authorization(root.adapter_key, setup, runner),
           do: Adapters.record_provider_disconnected(root.id, root.capabilities_json)

    case result do
      {:error, reason} = error ->
        _recorded =
          Adapters.record_provider_failure(
            root.id,
            :disconnect,
            reason,
            root.capabilities_json
          )

        error

      success ->
        success
    end
  rescue
    _error ->
      _recorded =
        Adapters.record_provider_failure(
          root.id,
          :disconnect,
          :provider_disconnect_failed,
          root.capabilities_json
        )

      {:error, :provider_disconnect_failed}
  end

  defp disconnect_authorization("codex", setup, runner) do
    run_disconnect(
      runner,
      setup.executable,
      ["-c", ~s(cli_auth_credentials_store="file"), "logout"],
      %{"CODEX_HOME" => setup.home}
    )
  end

  defp disconnect_authorization("cursor_agent", setup, runner) do
    with {:ok, environment} <- CursorAgent.account_environment(setup.home) do
      run_disconnect(runner, setup.executable, ["logout"], environment)
    end
  end

  defp disconnect_authorization(_runtime, _setup, _runner),
    do: {:error, :provider_disconnect_unsupported}

  defp run_disconnect(runner, executable, args, environment) do
    case runner.(executable, args,
           env: Enum.sort(environment),
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {_output, _status} -> {:error, :provider_disconnect_failed}
    end
  end

  defp check_authorization(%ProviderAccount{adapter_key: "codex"} = account) do
    with {:ok, setup} <- account_setup(account),
         {:ok, probe} <-
           Codex.probe(
             path: setup.executable,
             codex_home: setup.home,
             credentials_store: "file",
             run_scoped_authenticated?: true
           ) do
      status = if(probe.authenticated?, do: "authenticated", else: "authentication_required")

      catalog =
        model_catalog(probe.authenticated?, fn ->
          Codex.available_models(path: setup.executable, codex_home: setup.home)
        end)

      Adapters.record_provider_status(account.id, status, account.capabilities_json, catalog)
    end
  end

  defp check_authorization(%ProviderAccount{adapter_key: "cursor_agent"} = account) do
    with {:ok, setup} <- account_setup(account),
         {:ok, probe} <-
           CursorAgent.probe(
             path: setup.executable,
             cursor_home: setup.home,
             run_scoped_authenticated?: true
           ) do
      status = if(probe.authenticated?, do: "authenticated", else: "authentication_required")

      catalog =
        model_catalog(probe.authenticated?, fn ->
          CursorAgent.available_models(path: setup.executable, cursor_home: setup.home)
        end)

      Adapters.record_provider_status(account.id, status, account.capabilities_json, catalog)
    end
  end

  defp check_authorization(%ProviderAccount{} = account), do: {:ok, account}

  defp model_catalog(false, _discover),
    do: %{"status" => "authorization_required", "models" => []}

  defp model_catalog(true, discover) do
    case discover.() do
      {:ok, models} -> %{"status" => "available", "models" => models}
      {:error, _reason} -> %{"status" => "unavailable", "models" => []}
    end
  end

  def group_setups(setups) do
    setups
    |> Enum.group_by(fn setup ->
      {setup[:authorization_id] || setup[:account_id] || setup.role_key, setup.runtime,
       setup[:executable]}
    end)
    |> Enum.map(fn {_key, group} ->
      group = Enum.sort_by(group, & &1.role_key)
      Map.put(hd(group), :role_keys, Enum.map(group, & &1.role_key))
    end)
    |> Enum.sort_by(& &1.role_key)
  end

  defp role(skeleton, role_key) do
    skeleton.run.workflow_snapshot_json["roles"]
    |> Enum.find(&(&1["role_key"] == role_key and &1["role_kind"] == "agent"))
    |> case do
      nil ->
        {:error, :role_assignment_not_found}

      role ->
        settings = role["settings"] || %{}

        settings =
          case Cuckoding.AgentBindings.for_run(skeleton.run.id)[role_key] do
            nil -> settings
            id -> Map.put(settings, "provider_account_id", id)
          end

        {:ok,
         %{
           role_key: role["role_key"],
           adapter_key: role["adapter_key"],
           model_ref: role["model_ref"] || settings["model"],
           settings_json: settings
         }}
    end
  end

  defp adapter(skeleton, role) do
    path = role.settings_json["executable_path"]

    case role.adapter_key do
      "codex" ->
        with {:ok, shared} <- shared_options(role) do
          home =
            Keyword.get(
              shared,
              :codex_home,
              Path.join([skeleton.environment.run_dir, "agent", "codex", "home"])
            )

          probe(Codex, [path: path, codex_home: home, run_scoped_authenticated?: true] ++ shared)
        end

      "claude_code" ->
        probe(ClaudeCode,
          path: path,
          api_key_helper: role.settings_json["api_key_helper"],
          run_scoped_authenticated?: true
        )

      "cursor_agent" ->
        root = Path.join([skeleton.environment.run_dir, "agent", "cursor"])

        with {:ok, shared} <- shared_options(role) do
          probe(
            CursorAgent,
            [path: path, cursor_home: root, run_scoped_authenticated?: true] ++ shared
          )
        end

      "fake" ->
        {:ok, FakeAdapter, [], "test"}

      _other ->
        {:error, :unsupported_runtime}
    end
  end

  defp probe(module, options) do
    case module.probe(options) do
      {:ok, %{authenticated?: true, version: version}} ->
        {:ok, module, options, version}

      {:ok, _probe} ->
        if Keyword.has_key?(options, :shared_profile_id),
          do: {:error, :provider_auth_required},
          else: {:error, :run_scoped_auth_required}

      error ->
        error
    end
  end

  defp runtime_setup(skeleton, role) do
    case provider_account(role) do
      %ProviderAccount{adapter_key: runtime} = account
      when runtime in ["codex", "cursor_agent"] ->
        if runtime == role.adapter_key,
          do: account_setup(account),
          else: {:error, :provider_account_mismatch}

      _other ->
        legacy_setup(skeleton, role)
    end
  end

  defp legacy_setup(skeleton, role) do
    case role.adapter_key do
      "codex" ->
        home = Path.join([skeleton.environment.run_dir, "agent", "codex", "home"])
        prepare_directories([home])

        command =
          login_command(%{"CODEX_HOME" => home}, role.settings_json["executable_path"], [
            "login",
            "--device-auth"
          ])

        {:ok,
         %{
           runtime: "Codex",
           connection: role.settings_json["connection_label"],
           executable: role.settings_json["executable_path"],
           home: home,
           login_args: "login --device-auth",
           command: command,
           reusable?: false
         }}

      "claude_code" ->
        {:ok,
         %{
           runtime: "Claude Code",
           connection: role.settings_json["connection_label"],
           executable: role.settings_json["executable_path"],
           helper: role.settings_json["api_key_helper"]
         }}

      "cursor_agent" ->
        root = Path.join([skeleton.environment.run_dir, "agent", "cursor"])

        environment = %{
          "HOME" => Path.join(root, "home"),
          "CURSOR_CONFIG_DIR" => Path.join(root, "config"),
          "CLAUDE_CONFIG_DIR" => Path.join(root, "claude")
        }

        prepare_directories([root | Map.values(environment)])

        command =
          login_command(environment, role.settings_json["executable_path"], ["login"])

        {:ok,
         %{
           runtime: "Cursor Agent",
           connection: role.settings_json["connection_label"],
           executable: role.settings_json["executable_path"],
           environment: environment,
           login_args: "login",
           command: command
         }}

      "fake" ->
        {:ok,
         %{
           runtime: "Deterministic test adapter",
           connection: role.settings_json["connection_label"]
         }}

      _other ->
        {:error, :unsupported_runtime}
    end
  end

  defp prepare_directories(paths) do
    Enum.each(paths, fn path ->
      :ok = File.mkdir_p(path)
      :ok = File.chmod(path, 0o700)
    end)
  end

  defp login_command(environment, executable, args) do
    assignments =
      environment
      |> Enum.sort()
      |> Enum.map(fn {name, value} -> "#{name}=#{shell_quote(value)}" end)

    Enum.join(assignments ++ [shell_quote(executable) | Enum.map(args, &shell_arg/1)], " ")
  end

  defp shell_arg(value) do
    if Regex.match?(~r/\A[a-zA-Z0-9_\.\/:=+-]+\z/, value), do: value, else: shell_quote(value)
  end

  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\"'\"'") <> "'"

  defp shared_options(role) do
    case provider_account(role) do
      %ProviderAccount{adapter_key: runtime} = account when runtime == role.adapter_key ->
        with {:ok, root} <- Adapters.authorization_account(account),
             :ok <- Cuckoding.AgentBindings.compatible(runtime, role.settings_json, root.id),
             {:ok, home} <- SharedProfile.prepare(root.id, runtime) do
          {:ok, [shared_profile_id: root.id] ++ profile_options(runtime, home)}
        end

      nil ->
        if role.settings_json["provider_account_id"],
          do: {:error, :provider_account_not_found},
          else: {:ok, []}

      _other ->
        {:error, :provider_account_mismatch}
    end
  end

  defp profile_options("codex", home), do: [codex_home: home, credentials_store: "file"]
  defp profile_options("cursor_agent", _home), do: []

  defp provider_account(role) do
    role.settings_json["provider_account_id"]
    |> Adapters.get_provider_account()
  end

  defp authorization_identity(role) do
    case provider_account(role) do
      nil ->
        if role.settings_json["provider_account_id"],
          do: {:error, :provider_account_not_found},
          else: {:ok, nil}

      account ->
        with {:ok, root} <- Adapters.authorization_account(account),
             :ok <-
               Cuckoding.AgentBindings.compatible(role.adapter_key, role.settings_json, root.id),
             do: {:ok, root.id}
    end
  end

  defp runtime_name("claude_code"), do: "Claude Code"
  defp runtime_name("cursor_agent"), do: "Cursor Agent"
  defp runtime_name("opencode"), do: "OpenCode"
  defp runtime_name("custom_agent"), do: "Custom Agent"
  defp runtime_name(runtime), do: runtime
end
