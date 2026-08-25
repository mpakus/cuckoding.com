defmodule AgentDesk.Providers.MCPInjection do
  @moduledoc """
  Per-session Agent Hub MCP overlay. Never writes the user's global provider config.
  """

  alias AgentDesk.Agents.Session
  alias AgentDesk.Providers.Fixture
  alias AgentDesk.Storage

  import Bitwise

  @spec write!(Session.t(), String.t()) :: String.t()
  def write!(%Session{} = session, token) when is_binary(token) do
    dir = Storage.session_dir(session.project_id, session.id)
    ensure_private_dir!(dir)
    path = Path.join(dir, "mcp.json")

    config = %{
      "mcpServers" => %{
        "agentdesk-hub" => %{
          "command" => Fixture.elixir_executable(),
          "args" =>
            Fixture.code_path_args() ++
              ["-e", "AgentDesk.MCP.Stdio.main(System.argv())", "--", "--session", session.id],
          "env" => %{
            "AGENTDESK_CAPABILITY_TOKEN" => token,
            "AGENTDESK_SESSION_ID" => session.id,
            "AGENTDESK_PROJECT_ID" => session.project_id
          }
        }
      }
    }

    atomic_private_write!(path, Jason.encode!(config))

    if session.provider == "remote" do
      _ = write_connect_env!(session, token)
    end

    path
  end

  @spec cleanup(Session.t()) :: :ok
  def cleanup(%Session{} = session) do
    dir = Storage.session_dir(session.project_id, session.id)
    _ = File.rm(Path.join(dir, "mcp.json"))
    _ = File.rm(connect_env_path(session))
    :ok
  end

  @spec acp_servers(String.t()) :: [map()]
  def acp_servers(path) when is_binary(path) do
    with {:ok, body} <- File.read(path),
         {:ok, %{"mcpServers" => servers}} when is_map(servers) <- Jason.decode(body) do
      Enum.map(servers, &acp_server/1)
    else
      _ -> []
    end
  end

  defp acp_server({name, spec}) when is_map(spec) do
    %{
      "name" => to_string(name),
      "command" => spec["command"],
      "args" => List.wrap(spec["args"]),
      "env" => env_vars(spec["env"])
    }
  end

  defp env_vars(map) when is_map(map) do
    Enum.map(map, fn {key, value} ->
      %{"name" => to_string(key), "value" => to_string(value)}
    end)
  end

  defp env_vars(_), do: []

  @spec connect_env_path(Session.t()) :: String.t()
  def connect_env_path(%Session{} = session) do
    Path.join(Storage.session_dir(session.project_id, session.id), "connect.env")
  end

  @spec write_connect_env!(Session.t(), String.t()) :: String.t()
  def write_connect_env!(%Session{} = session, token) when is_binary(token) do
    path = connect_env_path(session)
    ensure_private_dir!(Path.dirname(path))

    body = """
    AGENTDESK_SESSION_ID=#{session.id}
    AGENTDESK_PROJECT_ID=#{session.project_id}
    AGENTDESK_CAPABILITY_TOKEN=#{token}
    """

    atomic_private_write!(path, body)
    path
  end

  defp ensure_private_dir!(dir) do
    root = Storage.ensure_data_root!()
    File.chmod!(root, 0o700)
    root_stat = private_directory_stat!(root)

    relative = Path.relative_to(dir, root)

    if relative == dir or relative == ".." or String.starts_with?(relative, "../") do
      raise File.Error, reason: :eacces, action: "contain private directory", path: dir
    end

    relative
    |> Path.split()
    |> Enum.reduce(root, fn component, parent ->
      path = Path.join(parent, component)
      ensure_private_component!(path, root_stat.uid)
      path
    end)

    :ok
  end

  defp ensure_private_component!(path, owner_uid) do
    case File.lstat(path) do
      {:ok, %{type: :directory, uid: ^owner_uid}} ->
        File.chmod!(path, 0o700)
        _ = private_directory_stat!(path)
        :ok

      {:ok, _stat} ->
        raise File.Error, reason: :eacces, action: "secure private directory", path: path

      {:error, :enoent} ->
        File.mkdir!(path)
        File.chmod!(path, 0o700)
        stat = private_directory_stat!(path)

        if stat.uid != owner_uid do
          raise File.Error, reason: :eacces, action: "secure directory ownership", path: path
        end

        :ok

      {:error, reason} ->
        raise File.Error, reason: reason, action: "inspect private directory", path: path
    end
  end

  defp private_directory_stat!(path) do
    stat = File.lstat!(path)

    if stat.type != :directory or (stat.mode &&& 0o777) != 0o700 do
      raise File.Error, reason: :eacces, action: "secure private directory", path: path
    end

    stat
  end

  defp atomic_private_write!(path, body) when is_binary(body) do
    dir = Path.dirname(path)
    dir_stat = private_directory_stat!(dir)
    reject_unsafe_target!(path, dir_stat.uid)
    temp = path <> ".tmp-" <> random_suffix()

    try do
      {:ok, :ok} =
        File.open(temp, [:write, :binary, :exclusive], fn io ->
          File.chmod!(temp, 0o600)
          ensure_owned_regular!(temp, dir_stat.uid)
          :ok = IO.binwrite(io, body)
          :ok = :file.sync(io)
        end)

      File.rename!(temp, path)
      File.chmod!(path, 0o600)
      ensure_owned_regular!(path, dir_stat.uid)
      :ok
    after
      _ = File.rm(temp)
    end
  end

  defp reject_unsafe_target!(path, owner_uid) do
    case File.lstat(path) do
      {:ok, %{type: :regular, uid: ^owner_uid}} ->
        :ok

      {:ok, _stat} ->
        raise File.Error, reason: :eacces, action: "replace private file", path: path

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        raise File.Error, reason: reason, action: "inspect private file", path: path
    end
  end

  defp ensure_owned_regular!(path, owner_uid) do
    stat = File.lstat!(path)

    if stat.type != :regular or stat.uid != owner_uid or (stat.mode &&& 0o777) != 0o600 do
      raise File.Error, reason: :eacces, action: "secure private file", path: path
    end

    :ok
  end

  defp random_suffix do
    12
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
