defmodule AgentDesk.Providers.Cursor do
  @moduledoc """
  Cursor Agent ACP adapter. Shares ACP framing with OpenCode; owns Cursor extensions.
  """

  @behaviour AgentDesk.Providers.Adapter

  alias AgentDesk.Providers.ACP.Client
  alias AgentDesk.Providers.Capabilities
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Discovery
  alias AgentDesk.Providers.Fixture

  @binaries ~w(agent cursor-agent cursor)

  @impl true
  def key, do: "cursor"

  @impl true
  def display_name, do: "Cursor"

  @impl true
  def capabilities do
    %Capabilities{
      key: key(),
      structured_events: true,
      multi_turn: true,
      resume: true,
      steer_active_turn: false,
      approvals: true,
      mcp_stdio: true,
      mcp_http: true,
      file_change_events: true,
      usage_events: true,
      structured_output: true,
      internal_a2a: true,
      safe_boundary_delivery: true
    }
  end

  @impl true
  def probe(opts) do
    if Fixture.enabled?(opts) do
      {:ok, %{key: key(), executable: "fixture", version: "fixture", protocol: "fixture"}}
    else
      with {:ok, executable, _args} <- resolve(opts),
           {:ok, executable} <-
             Discovery.find_executable(executable, executable: executable) do
        version = probe_version(executable, opts)
        {:ok, %{key: key(), executable: executable, version: version}}
      end
    end
  end

  @spec resolve(keyword()) :: {:ok, String.t(), [String.t()]} | {:error, term()}
  def resolve(opts \\ []) do
    case Keyword.get(opts, :executable) do
      exe when is_binary(exe) and exe != "" ->
        {:ok, exe, acp_args(exe)}

      _ ->
        case Discovery.find_first(@binaries, opts) do
          {:ok, path} -> {:ok, path, acp_args(path)}
          error -> error
        end
    end
  end

  @impl true
  def command_spec(session, opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    if Fixture.enabled?(opts ++ [fixture: session.settings["fixture"]]) do
      {:ok,
       Fixture.command_spec(
         "acp",
         Keyword.merge(opts,
           cwd: cwd,
           peer_args: ["--vendor", "cursor"] ++ Keyword.get(opts, :peer_args, [])
         )
       )}
    else
      case resolve(opts) do
        {:ok, executable, args} ->
          {:ok,
           %CommandSpec{
             executable: executable,
             args: args,
             cwd: cwd,
             env_passthrough: AgentDesk.Env.provider_env_passthrough(key())
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def init_decode, do: Client.new(key())

  @impl true
  def decode_line(line, state), do: Client.decode_line(state, line)

  @impl true
  def encode(action, state), do: Client.encode(state, action)

  defp acp_args(path) when is_binary(path) do
    case path |> Path.basename() |> String.downcase() do
      name when name in ["cursor", "cursor.exe"] -> ["agent", "acp"]
      _ -> ["acp"]
    end
  end

  defp probe_version(executable, opts) do
    if Keyword.has_key?(opts, :executable) do
      "configured"
    else
      case Discovery.version(executable) do
        {:ok, version} -> version
        _ -> "installed"
      end
    end
  end
end
