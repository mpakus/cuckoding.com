defmodule Cuckoding.AgentRuntime do
  @moduledoc "Resolves one snapshotted role to its isolated provider runtime."

  alias Cuckoding.Adapters
  alias Cuckoding.Adapters.ClaudeCode
  alias Cuckoding.Adapters.Codex
  alias Cuckoding.Adapters.CursorAgent
  alias Cuckoding.Adapters.FakeAdapter
  alias Cuckoding.Adapters.ProviderAccount

  def resolve(skeleton, role_key) when is_binary(role_key) do
    with {:ok, role} <- role(skeleton, role_key),
         {:ok, adapter, options, version} <- adapter(skeleton, role) do
      {:ok,
       %{
         adapter: adapter,
         options: options,
         version: version,
         settings: role.settings_json,
         role_key: role.role_key
       }}
    end
  end

  def setup(skeleton, role_key) when is_binary(role_key) do
    with {:ok, role} <- role(skeleton, role_key),
         {:ok, setup} <- runtime_setup(skeleton, role) do
      {:ok, Map.put(setup, :role_key, role_key)}
    end
  end

  def account_setup(%ProviderAccount{adapter_key: "codex"} = account) do
    home = account_home(account)
    executable = get_in(account.capabilities_json, ["settings", "executable_path"])

    if is_binary(executable) and executable != "" do
      prepare_directories([home])

      {:ok,
       %{
         runtime: "Codex",
         connection: account.label,
         executable: executable,
         home: home,
         command:
           login_command(%{"CODEX_HOME" => home}, executable, [
             "-c",
             ~s(cli_auth_credentials_store="keyring"),
             "login",
             "--device-auth"
           ]),
         reusable?: true,
         status: account.status
       }}
    else
      {:error, :runtime_executable_missing}
    end
  end

  def account_setup(%ProviderAccount{} = account) do
    {:ok,
     %{
       runtime: runtime_name(account.adapter_key),
       connection: account.label,
       reusable?: account.auth_mode == "api_key_helper",
       status: account.status
     }}
  end

  def check_account(%ProviderAccount{adapter_key: "codex"} = account) do
    with {:ok, setup} <- account_setup(account),
         {:ok, probe} <-
           Codex.probe(
             path: setup.executable,
             codex_home: setup.home,
             credentials_store: "keyring",
             run_scoped_authenticated?: true
           ) do
      status = if(probe.authenticated?, do: "authenticated", else: "authentication_required")
      Adapters.record_provider_status(account.id, status)
    end
  end

  def check_account(%ProviderAccount{} = account), do: {:ok, account}

  defp role(skeleton, role_key) do
    skeleton.run.workflow_snapshot_json["roles"]
    |> Enum.find(&(&1["role_key"] == role_key and &1["role_kind"] == "agent"))
    |> case do
      nil ->
        {:error, :role_assignment_not_found}

      role ->
        {:ok,
         %{
           role_key: role["role_key"],
           adapter_key: role["adapter_key"],
           settings_json: role["settings"] || %{}
         }}
    end
  end

  defp adapter(skeleton, role) do
    path = role.settings_json["executable_path"]

    case role.adapter_key do
      "codex" ->
        home = Path.join([skeleton.environment.run_dir, "agent", "codex", "home"])

        options =
          [path: path, codex_home: home, run_scoped_authenticated?: true] ++
            shared_credentials(role)

        probe(Codex, options)

      "claude_code" ->
        probe(ClaudeCode,
          path: path,
          api_key_helper: role.settings_json["api_key_helper"],
          run_scoped_authenticated?: true
        )

      "cursor_agent" ->
        root = Path.join([skeleton.environment.run_dir, "agent", "cursor"])
        probe(CursorAgent, path: path, cursor_home: root, run_scoped_authenticated?: true)

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
        if Keyword.get(options, :credentials_store) == "keyring",
          do: {:error, :provider_auth_required},
          else: {:error, :run_scoped_auth_required}

      error ->
        error
    end
  end

  defp runtime_setup(skeleton, role) do
    case role.adapter_key do
      "codex" ->
        account = provider_account(role)

        {home, command, reusable?} =
          case account do
            %ProviderAccount{auth_mode: "os_keyring"} = account ->
              {:ok, setup} = account_setup(account)
              {setup.home, setup.command, true}

            _other ->
              home = Path.join([skeleton.environment.run_dir, "agent", "codex", "home"])
              prepare_directories([home])

              command =
                login_command(%{"CODEX_HOME" => home}, role.settings_json["executable_path"], [
                  "login",
                  "--device-auth"
                ])

              {home, command, false}
          end

        {:ok,
         %{
           runtime: "Codex",
           connection: role.settings_json["connection_label"],
           executable: role.settings_json["executable_path"],
           home: home,
           login_args: "login --device-auth",
           command: command,
           reusable?: reusable?
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

  defp shared_credentials(role) do
    case provider_account(role) do
      %ProviderAccount{auth_mode: "os_keyring"} -> [credentials_store: "keyring"]
      _other -> []
    end
  end

  defp provider_account(role) do
    role.settings_json["provider_account_id"]
    |> Adapters.get_provider_account()
  end

  defp account_home(account) do
    root =
      Application.get_env(:cuckoding, :provider_account_root) ||
        Path.join([
          System.user_home!(),
          "Library",
          "Application Support",
          "Cuckoding",
          "provider-accounts"
        ])

    Path.join([root, account.id, "codex-home"])
  end

  defp runtime_name("claude_code"), do: "Claude Code"
  defp runtime_name("cursor_agent"), do: "Cursor Agent"
  defp runtime_name("opencode"), do: "OpenCode"
  defp runtime_name("custom_agent"), do: "Custom Agent"
  defp runtime_name(runtime), do: runtime
end
