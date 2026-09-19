defmodule Cuckoding.AgentRuntime do
  @moduledoc "Resolves one snapshotted role to its isolated provider runtime."

  alias Cuckoding.Adapters.ClaudeCode
  alias Cuckoding.Adapters.Codex
  alias Cuckoding.Adapters.CursorAgent
  alias Cuckoding.Adapters.FakeAdapter

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
        probe(Codex, path: path, codex_home: home, run_scoped_authenticated?: true)

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
      {:ok, %{authenticated?: true, version: version}} -> {:ok, module, options, version}
      {:ok, _probe} -> {:error, :run_scoped_auth_required}
      error -> error
    end
  end

  defp runtime_setup(skeleton, role) do
    case role.adapter_key do
      "codex" ->
        home = Path.join([skeleton.environment.run_dir, "agent", "codex", "home"])
        prepare_directories([home])

        {:ok,
         %{
           runtime: "Codex",
           connection: role.settings_json["connection_label"],
           executable: role.settings_json["executable_path"],
           home: home,
           login_args: "login --device-auth"
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

        {:ok,
         %{
           runtime: "Cursor Agent",
           connection: role.settings_json["connection_label"],
           executable: role.settings_json["executable_path"],
           environment: environment,
           login_args: "login"
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
end
