defmodule Boss.Agents.Authorizer do
  @moduledoc """
  Initiates CLI authorization via native browser OAuth or an interactive macOS
  Terminal session, then re-verifies status and fetches supported models.
  No credentials or terminal I/O are captured or stored.
  """
  alias Boss.Agents.{Detections, Metadata, ModelDiscovery}
  alias Boss.Agents.Process, as: Runner

  @browser_login ~w(codex claude cursor)a

  def login_argv(:codex), do: ["login"]
  def login_argv(:claude), do: ["auth", "login"]
  def login_argv(:cursor), do: ["login"]
  def login_argv(:hermes), do: ["auth", "add"]
  def login_argv(:pi), do: ["auth", "login"]
  def login_argv(:opencode), do: ["auth", "login"]

  def authorize(agent_id, mode \\ :auto) when is_atom(agent_id) do
    path = executable_for(agent_id)

    cond do
      is_nil(path) ->
        {:error, :not_installed}

      mode == :terminal or agent_id not in @browser_login ->
        open_in_terminal(path, login_argv(agent_id))

      true ->
        case run_browser_login(path, login_argv(agent_id)) do
          :ok ->
            verify_and_fetch(agent_id)

          {:error, :tty_required} ->
            open_in_terminal(path, login_argv(agent_id))

          {:error, _} = err ->
            err
        end
    end
  end

  def verify_and_fetch(agent_id) when is_atom(agent_id) do
    detector = Application.get_env(:boss, :agent_detector, Boss.Agents.Detector)
    discovery = Application.get_env(:boss, :agent_model_discovery, ModelDiscovery)

    with {:ok, scanned} <- scan_single(detector, agent_id) do
      scanned = maybe_probe_opencode_auth(scanned)
      saved = Detections.save_agent(scanned)

      if saved.probe_status == :ok and saved.auth_status == :configured do
        case discovery.fetch(agent_id, saved.path) do
          {:ok, models} ->
            {:ok, Detections.save_models(agent_id, models) || %{saved | models: models}}

          {:error, :auth_required} ->
            {:ok,
             Detections.mark_auth_status(agent_id, :stale) ||
               %{saved | auth_status: :stale, models: []}}

          _ ->
            {:ok, saved}
        end
      else
        {:ok, saved}
      end
    end
  end

  def fetch_models(agent_id) when is_atom(agent_id) do
    discovery = Application.get_env(:boss, :agent_model_discovery, ModelDiscovery)

    case Detections.get_view(agent_id) do
      %{probe_status: :ok, auth_status: :configured, path: path} = current ->
        case discovery.fetch(agent_id, path) do
          {:ok, models} ->
            {:ok, Detections.save_models(agent_id, models) || %{current | models: models}}

          {:error, :auth_required} ->
            updated =
              Detections.mark_auth_status(agent_id, :stale) ||
                %{current | auth_status: :stale, models: []}

            {:error, {:auth_required, updated}}

          {:error, reason} ->
            {:error, reason}
        end

      %{probe_status: :ok} ->
        {:error, :not_authorized}

      _ ->
        {:error, :not_detected}
    end
  end

  defp scan_single(detector, agent_id) do
    if function_exported?(detector, :scan_agent, 1) do
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

  defp maybe_probe_opencode_auth(%{id: :opencode, probe_status: :ok, path: path} = row)
       when is_binary(path) do
    if File.regular?(path) do
      scratch = Path.join(System.tmp_dir!(), "boss-opencode-auth-#{Ecto.UUID.generate()}")

      status =
        with :ok <- File.mkdir(scratch),
             :ok <- File.chmod(scratch, 0o700) do
          check_opencode_credentials(path, scratch)
        else
          _ -> row.auth_status
        end

      File.rm_rf(scratch)
      %{row | auth_status: status}
    else
      row
    end
  end

  defp maybe_probe_opencode_auth(row), do: row

  defp check_opencode_credentials(path, scratch) do
    capture = :ets.new(:opencode_auth_count, [:set, :public])
    :ets.insert(capture, {:out, ""})

    try do
      result =
        Runner.run(path, ["auth", "list"],
          cd: scratch,
          input: "",
          timeout_ms: 6_000,
          output_limit: 32_768,
          on_event: fn
            {:stdout, b} ->
              [{:out, cur}] = :ets.lookup(capture, :out)
              if byte_size(cur) < 16_384, do: :ets.insert(capture, {:out, cur <> b})
              :ok

            _ ->
              :ok
          end
        )

      [{:out, raw}] = :ets.lookup(capture, :out)
      clean = Regex.replace(~r/\e\[[0-9;]*[A-Za-z]/, raw, "")

      cond do
        result.exit_code != 0 ->
          :unknown

        Regex.match?(~r/\b0\s+credentials?\b/i, clean) ->
          :not_configured

        Regex.match?(~r/\b[1-9]\d*\s+credentials?\b/i, clean) ->
          :configured

        true ->
          :unknown
      end
    after
      :ets.delete(capture)
    end
  end

  defp executable_for(agent_id) do
    case Detections.get_view(agent_id) do
      %{path: path} when is_binary(path) -> path
      _ -> Metadata.find_executable(agent_id)
    end
  end

  defp run_browser_login(path, argv) do
    scratch = Path.join(System.tmp_dir!(), "boss-agent-login-#{Ecto.UUID.generate()}")

    with :ok <- File.mkdir(scratch),
         :ok <- File.chmod(scratch, 0o700) do
      result =
        Runner.run(path, argv,
          cd: scratch,
          input: "",
          timeout_ms: 180_000,
          output_limit: 65_536
        )

      if result.cleanup == :group_empty, do: File.rm_rf(scratch)

      cond do
        result.outcome == :exited and result.exit_kind == :exit and result.exit_code == 0 ->
          :ok

        result.outcome == :exited ->
          {:error, :tty_required}

        true ->
          {:error, :login_timeout}
      end
    else
      _ ->
        File.rm_rf(scratch)
        {:error, :unavailable}
    end
  end

  defp open_in_terminal(path, argv) do
    case :os.type() do
      {:unix, :darwin} ->
        command_line = Enum.map_join([path | argv], " ", &shell_escape/1)

        script = """
        on run argv
          tell application "Terminal"
            activate
            do script (item 1 of argv)
          end tell
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
