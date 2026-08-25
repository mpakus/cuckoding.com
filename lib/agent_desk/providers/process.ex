defmodule AgentDesk.Providers.Process do
  @moduledoc false

  alias AgentDesk.Agents.Session
  alias AgentDesk.Env
  alias AgentDesk.Isolation
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Discovery
  alias AgentDesk.Storage

  @stderr_chunk_bytes 16_384

  @type identity :: %{
          required(String.t()) => integer() | String.t() | nil
        }

  @spec open(CommandSpec.t(), String.t(), Session.t()) ::
          {:ok, port(), identity(), Path.t()} | {:error, term()}
  def open(%CommandSpec{} = spec, token, %Session{} = session) do
    with {:ok, executable} <- Discovery.find_executable(spec.executable),
         {:ok, perl} <- perl_executable(),
         {:ok, wrapper} <- wrapper_path(),
         {:ok, env} <- provider_environment(spec, token, session) do
      stderr_path = stderr_path(session)
      File.mkdir_p!(Path.dirname(stderr_path))
      File.write!(stderr_path, "", [:append])
      File.chmod!(stderr_path, 0o600)

      port =
        Port.open({:spawn_executable, perl}, [
          :binary,
          :exit_status,
          :use_stdio,
          {:args, [wrapper, stderr_path, executable | spec.args]},
          {:cd, spec.cwd},
          {:env, env}
        ])

      os_pid = os_pid(port)

      {:ok, port,
       %{
         "os_pid" => os_pid,
         "process_group_id" => os_pid,
         "port" => inspect(port),
         "stderr_capture" => stderr_path
       }, stderr_path}
    end
  rescue
    error in [ArgumentError, ErlangError, File.Error] ->
      {:error, {:spawn_failed, Exception.message(error)}}
  end

  @spec signal_group(integer() | nil, :term | :kill) :: :ok | {:error, term()}
  def signal_group(pid, signal) when is_integer(pid) and pid > 0 do
    with {:ok, kill} <- kill_executable() do
      flag = if signal == :kill, do: "-KILL", else: "-TERM"

      case System.cmd(kill, [flag, "-#{pid}"], stderr_to_stdout: true) do
        {_output, 0} ->
          :ok

        {output, status} ->
          {:error, {:signal_failed, signal, status, String.slice(output, 0, 500)}}
      end
    end
  rescue
    error in [ArgumentError, ErlangError] ->
      {:error, {:signal_failed, signal, Exception.message(error)}}
  end

  def signal_group(_pid, signal), do: {:error, {:signal_failed, signal, :missing_process_group}}

  @spec alive?(port() | nil) :: boolean()
  def alive?(port) when is_port(port), do: Port.info(port) != nil
  def alive?(_port), do: false

  @spec close(port() | nil) :: :ok
  def close(port) when is_port(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  end

  def close(_port), do: :ok

  @spec read_stderr(Path.t() | nil, non_neg_integer()) ::
          {:ok, binary(), non_neg_integer()} | {:error, term()}
  def read_stderr(nil, offset), do: {:ok, "", offset}

  def read_stderr(path, offset) when is_binary(path) and is_integer(offset) and offset >= 0 do
    case :file.open(path, [:read, :binary, :raw]) do
      {:ok, io} ->
        result =
          case :file.pread(io, offset, @stderr_chunk_bytes) do
            {:ok, data} -> {:ok, data, offset + byte_size(data)}
            :eof -> {:ok, "", offset}
            {:error, reason} -> {:error, reason}
          end

        :ok = :file.close(io)
        result

      {:error, :enoent} ->
        {:ok, "", offset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> pid
      _ -> nil
    end
  end

  defp provider_environment(spec, token, session) do
    explicit =
      session
      |> Isolation.env()
      |> Map.merge(spec.env)
      |> Map.put("AGENTDESK_CAPABILITY_TOKEN", token)

    Env.provider_port_environment(explicit, spec.env_passthrough, System.get_env())
  end

  defp perl_executable do
    case System.find_executable("perl") do
      nil -> {:error, :provider_process_wrapper_unavailable}
      path -> {:ok, path}
    end
  end

  defp kill_executable do
    case System.find_executable("kill") do
      nil -> {:error, :kill_executable_unavailable}
      path -> {:ok, path}
    end
  end

  defp wrapper_path do
    path = Application.app_dir(:agent_desk, "priv/provider_process_wrapper.pl")
    if File.regular?(path), do: {:ok, path}, else: {:error, :provider_process_wrapper_missing}
  end

  defp stderr_path(%Session{} = session) do
    Path.join(Storage.session_dir(session.project_id, session.id), "provider-stderr.log")
  end
end
