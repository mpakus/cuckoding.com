defmodule AgentDesk.Providers.AcpGeneric do
  @moduledoc """
  ACP adapter for agents installed from the ACP Registry.

  Command specs come from the install record (executable + argv). Native
  Codex/Claude/Cursor/OpenCode adapters remain the first-class path when
  those CLIs are mapped.
  """

  @behaviour AgentDesk.Providers.Adapter

  alias AgentDesk.Agents.Session
  alias AgentDesk.Providers.ACP.Client
  alias AgentDesk.Providers.Capabilities
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Fixture

  @impl true
  def key, do: "acp"

  @impl true
  def display_name, do: "ACP"

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
      {:ok, %{key: key(), executable: "fixture", version: "fixture", protocol: "acp"}}
    else
      {:ok, %{key: key(), protocol: "acp"}}
    end
  end

  @impl true
  def command_spec(%Session{} = session, opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    if Fixture.enabled?(opts ++ [fixture: session.settings["fixture"]]) do
      {:ok,
       Fixture.command_spec(
         "acp",
         Keyword.merge(opts,
           cwd: cwd,
           peer_args: ["--vendor", "acp"] ++ Keyword.get(opts, :peer_args, [])
         )
       )}
    else
      user_spec(session, opts, cwd)
    end
  end

  @impl true
  def init_decode, do: Client.new(key())

  @impl true
  def decode_line(line, state), do: Client.decode_line(state, line)

  @impl true
  def encode(action, state), do: Client.encode(state, action)

  defp user_spec(session, opts, cwd) do
    with {:ok, executable} <-
           locate(Keyword.get(opts, :executable) || session.settings["acp_executable"]),
         {:ok, args} <- args(session.settings["acp_args"]) do
      {:ok, %CommandSpec{executable: executable, args: args, cwd: cwd}}
    end
  end

  defp locate(path) when is_binary(path) do
    trimmed = String.trim(path)

    cond do
      trimmed == "" or String.contains?(trimmed, "\0") ->
        {:error, :invalid_executable}

      Path.type(trimmed) == :absolute and File.regular?(trimmed) ->
        {:ok, trimmed}

      relative_command?(trimmed) ->
        case System.find_executable(trimmed) do
          nil -> {:error, :not_found}
          found -> {:ok, found}
        end

      true ->
        {:error, :invalid_executable}
    end
  end

  defp locate(_), do: {:error, :invalid_executable}

  defp relative_command?(name) do
    Path.type(name) == :relative and not String.contains?(name, "/") and
      not String.contains?(name, "\\")
  end

  defp args(list) when is_list(list) do
    cleaned =
      list
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.contains?(&1, "\0")))
      |> Enum.take(32)

    {:ok, cleaned}
  end

  defp args(_), do: {:ok, []}
end
