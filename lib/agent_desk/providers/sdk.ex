defmodule AgentDesk.Providers.SDK do
  @moduledoc """
  Structured JSONL adapter for user-supplied SDK or CLI agents.

  The child speaks newline JSON events (`type`) and accepts newline JSON
  commands (`op`). Commands are an executable plus an argument array, never a
  shell string. See `docs/PROVIDERS.md`.
  """

  @behaviour AgentDesk.Providers.Adapter

  alias AgentDesk.Agents.Session
  alias AgentDesk.Providers.Capabilities
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Event
  alias AgentDesk.Providers.Fixture
  alias AgentDesk.Providers.Probe

  @impl true
  def key, do: "sdk"

  @impl true
  def display_name, do: "SDK"

  @impl true
  def capabilities do
    %Capabilities{
      key: key(),
      structured_events: true,
      multi_turn: true,
      resume: false,
      approvals: true,
      mcp_stdio: true,
      usage_events: true,
      structured_output: true,
      internal_a2a: true,
      safe_boundary_delivery: true,
      spawned: true
    }
  end

  @impl true
  def probe(opts), do: Probe.probe(key(), "elixir", opts)

  @impl true
  def command_spec(%Session{} = session, opts) do
    if Fixture.enabled?(opts) do
      {:ok, Fixture.command_spec("sdk", opts)}
    else
      user_spec(session, opts)
    end
  end

  @impl true
  def init_decode, do: %{}

  @impl true
  def decode_line(line, state) do
    case Jason.decode(line) do
      {:ok, %{"type" => type} = payload} ->
        case Event.type_from_string(type) do
          {:ok, event_type} ->
            {:ok, [Event.new(event_type, payload, key())], state}

          :error ->
            {:ok, [], state}
        end

      {:ok, _} ->
        {:ok, [], state}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  @impl true
  def encode(:initialize, state), do: command(%{"op" => "initialize"}, state)
  def encode(:initialized, state), do: command(%{"op" => "initialized"}, state)

  def encode({:start_session, cwd}, state),
    do: command(%{"op" => "start_session", "cwd" => cwd}, state)

  def encode({:resume, id}, state),
    do: command(%{"op" => "resume", "provider_session_id" => id}, state)

  def encode({:prompt, text}, state), do: command(%{"op" => "prompt", "text" => text}, state)
  def encode(:interrupt, state), do: command(%{"op" => "interrupt"}, state)

  def encode({:approve, request_id, decision}, state) do
    command(%{"op" => "approve", "request_id" => request_id, "decision" => decision}, state)
  end

  def encode({:configure_mcp, path}, state) do
    command(%{"op" => "configure_mcp", "path" => path}, state)
  end

  def encode(_action, _state), do: {:error, :unsupported_action}

  defp command(map, state), do: {:ok, Jason.encode!(map) <> "\n", state}

  defp user_spec(session, opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    with {:ok, executable} <- resolve_executable(session, opts),
         {:ok, args} <- resolve_args(session) do
      {:ok, %CommandSpec{executable: executable, args: args, cwd: cwd}}
    end
  end

  defp resolve_executable(session, opts) do
    opts
    |> Keyword.get(:executable)
    |> Kernel.||(session.settings["sdk_executable"])
    |> locate()
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

  defp resolve_args(%Session{settings: settings}) do
    args =
      case settings["sdk_args"] do
        list when is_list(list) -> list
        text when is_binary(text) -> String.split(text, "\n")
        _ -> []
      end

    cleaned =
      args
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(32)

    if Enum.any?(cleaned, &(String.length(&1) > 500 or String.contains?(&1, "\0"))) do
      {:error, :invalid_args}
    else
      {:ok, cleaned}
    end
  end
end
