defmodule Boss.Agents.Authorizer do
  @moduledoc """
  Opens interactive sign-in in macOS Terminal and refreshes local model metadata.
  No credentials or terminal I/O are captured or stored.
  """
  alias Boss.Agents.{Detections, ModelDiscovery}

  def login_argv(:codex), do: ["login"]
  def login_argv(:claude), do: ["auth", "login"]
  def login_argv(:cursor), do: ["login"]
  def login_argv(:hermes), do: ["model"]
  def login_argv(:pi), do: []
  def login_argv(:opencode), do: ["auth", "login"]

  def authorize(agent_id, _mode \\ :auto) when is_atom(agent_id) do
    detector = Application.get_env(:boss, :agent_detector, Boss.Agents.Detector)

    case scan_single(detector, agent_id) do
      {:ok, %{probe_status: :ok, path: path}} when is_binary(path) ->
        open_in_terminal(path, login_argv(agent_id))

      {:ok, _} ->
        {:error, :not_installed}

      error ->
        error
    end
  end

  def verify_and_fetch(agent_id) when is_atom(agent_id) do
    with {:ok, saved, _} <- refresh(agent_id) do
      {:ok, saved}
    end
  end

  def fetch_models(agent_id) when is_atom(agent_id) do
    case refresh(agent_id) do
      {:ok, %{probe_status: :ok, auth_status: :configured} = saved, true} ->
        {:ok, saved}

      {:ok, %{probe_status: :ok, auth_status: :configured}, false} ->
        {:error, :unavailable}

      {:ok, %{probe_status: :ok, auth_status: :stale} = saved, _} ->
        {:error, {:auth_required, saved}}

      {:ok, %{probe_status: :ok}, _} ->
        {:error, :not_authorized}

      {:ok, _, _} ->
        {:error, :not_detected}

      error ->
        error
    end
  end

  def enrich(%{probe_status: :ok, auth_status: auth, id: id} = row, discovery)
      when auth == :configured or (auth == :unknown and id in [:pi, :hermes, :opencode]) do
    case discovery.fetch(id, row.path) do
      {:ok, []} when auth == :unknown ->
        row

      {:ok, models} ->
        row |> Map.put(:auth_status, :configured) |> Map.put(:models, models)

      {:error, :auth_required} ->
        status = if auth == :configured, do: :stale, else: :not_configured
        %{row | auth_status: status}

      {:error, reason} when reason in [:unavailable, :invalid_models] ->
        %{row | errors: row.errors ++ [%{stage: :models, reason: reason}]}
    end
  end

  def enrich(row, _discovery), do: row

  defp refresh(agent_id) do
    detector = Application.get_env(:boss, :agent_detector, Boss.Agents.Detector)
    discovery = Application.get_env(:boss, :agent_model_discovery, ModelDiscovery)
    checked_at = DateTime.utc_now()

    with {:ok, row} <- scan_single(detector, agent_id) do
      row = enrich(row, discovery)
      {:ok, Detections.save_agent(row, checked_at), Map.has_key?(row, :models)}
    end
  end

  defp scan_single(detector, agent_id) do
    if Code.ensure_loaded?(detector) and function_exported?(detector, :scan_agent, 1) do
      detector.scan_agent(agent_id)
    else
      case detector.scan() do
        {:ok, rows} ->
          case Enum.find(rows, &(&1.id == agent_id)) do
            nil -> {:error, :not_detected}
            row -> {:ok, row}
          end

        error ->
          error
      end
    end
  end

  defp open_in_terminal(path, argv) do
    case :os.type() do
      {:unix, :darwin} ->
        command_line = "cd / && " <> Enum.map_join([path | argv], " ", &shell_escape/1)

        script = """
        on run argv
          with timeout of 15 seconds
            tell application "Terminal"
              activate
              do script (item 1 of argv)
            end tell
          end timeout
        end run
        """

        case System.cmd("/usr/bin/osascript", ["-e", script, command_line],
               stderr_to_stdout: true
             ) do
          {_, 0} -> {:ok, :terminal_opened}
          _ -> {:error, :terminal_unavailable}
        end

      _ ->
        {:error, :terminal_unavailable}
    end
  end

  defp shell_escape(arg) do
    "'" <> String.replace(arg, "'", "'\\''") <> "'"
  end
end
