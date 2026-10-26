defmodule Boss.Agents.Detector do
  @moduledoc """
  Bounded local CLI metadata probes, with one scan owned by its caller.

  Capabilities describe help text only. Auth status describes reported credential
  configuration, not model access or quota. Only fixed version/help/status argv are
  executed, from a fresh scratch directory. Cleanup owns the direct child; this is
  not the production runner's process-tree or stream-backpressure boundary.
  """
  use GenServer
  alias Boss.Agents.Metadata

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def scan(server \\ __MODULE__) do
    GenServer.call(server, :scan, :infinity)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       active: nil,
       executables: Keyword.get(opts, :executables),
       os_type: Keyword.get(opts, :os_type, :os.type()),
       probe_timeout_ms: limit(opts, :probe_timeout_ms, 5000),
       scan_timeout_ms: limit(opts, :scan_timeout_ms, 30_000),
       output_limit: limit(opts, :output_limit, 65_536)
     }}
  end

  @impl true
  def handle_call(:scan, _from, %{active: active} = state) when active != nil,
    do: {:reply, {:error, :busy}, state}

  def handle_call(:scan, from, state) do
    if state.os_type in [{:unix, :darwin}, {:unix, :linux}] do
      begin_scan(from, state)
    else
      {:reply,
       {:ok, Enum.map([:codex, :claude], &%{Metadata.new(&1, nil) | probe_status: :unsupported})},
       state}
    end
  end

  @impl true
  def handle_info({port, {:data, bytes}}, %{active: %{port: port} = active} = state) do
    if byte_size(active.output) + byte_size(bytes) <= state.output_limit do
      {:noreply, %{state | active: %{active | output: active.output <> bytes}}}
    else
      stop_child(port)
      complete_probe({:error, :output_limit}, state)
    end
  end

  def handle_info({port, {:exit_status, code}}, %{active: %{port: port} = active} = state),
    do: complete_probe({:ok, active.output, code}, state)

  def handle_info({:probe_timeout, port}, %{active: %{port: port}} = state) do
    stop_child(port)
    complete_probe({:error, :timeout}, state)
  end

  def handle_info({:scan_timeout, monitor}, %{active: %{monitor: monitor}} = state),
    do: finish({:error, :unavailable}, state)

  def handle_info({:DOWN, monitor, :process, _, _}, %{active: %{monitor: monitor}} = state),
    do: finish({:error, :cancelled}, state)

  def handle_info({:EXIT, port, reason}, %{active: %{port: port}} = state) when reason != :normal,
    do: complete_probe({:error, :exit_status}, state)

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, %{active: active}) when active != nil, do: cleanup(active)
  def terminate(_, _), do: :ok

  @impl true
  def format_status(status), do: Map.new(status, fn {key, _} -> {key, :redacted} end)

  defp begin_scan(from, state) do
    case create_directory() do
      {:ok, directory} ->
        monitor = Process.monitor(elem(from, 0))
        scan_timer = Process.send_after(self(), {:scan_timeout, monitor}, state.scan_timeout_ms)

        active = %{
          from: from,
          monitor: monitor,
          scan_timer: scan_timer,
          directory: directory,
          remaining: [:codex, :claude],
          results: [],
          agent: nil,
          steps: [],
          step: nil,
          port: nil,
          probe_timer: nil,
          output: ""
        }

        advance(%{state | active: active})

      {:error, _} ->
        {:reply, {:error, :unavailable}, state}
    end
  end

  defp create_directory do
    directory =
      Path.join(
        System.tmp_dir!(),
        "boss-probe-#{Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)}"
      )

    with :ok <- File.mkdir(directory) do
      case File.chmod(directory, 0o700) do
        :ok ->
          {:ok, directory}

        {:error, reason} ->
          File.rmdir(directory)
          {:error, reason}
      end
    end
  end

  defp advance(%{active: active} = state) do
    cond do
      not Process.alive?(elem(active.from, 0)) ->
        finish({:error, :cancelled}, state)

      active.steps != [] ->
        start_probe(state)

      active.agent != nil ->
        advance(%{
          state
          | active: %{active | results: [active.agent | active.results], agent: nil}
        })

      active.remaining == [] ->
        finish({:ok, Enum.reverse(active.results)}, state)

      true ->
        [id | remaining] = active.remaining

        path =
          if state.executables,
            do: Map.get(state.executables, id),
            else: System.find_executable(Atom.to_string(id))

        agent = Metadata.new(id, path)

        advance(%{
          state
          | active: %{
              active
              | remaining: remaining,
                agent: agent,
                steps: if(path, do: [:version], else: [])
            }
        })
    end
  end

  defp start_probe(%{active: active} = state) do
    [step | steps] = active.steps
    active = %{active | step: step, steps: steps}

    try do
      port =
        Port.open({:spawn_executable, active.agent.path}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          :hide,
          args: Metadata.argv(active.agent.id, step),
          cd: active.directory
        ])

      timer = Process.send_after(self(), {:probe_timeout, port}, state.probe_timeout_ms)
      {:noreply, %{state | active: %{active | port: port, probe_timer: timer, output: ""}}}
    rescue
      _ in [ArgumentError, ErlangError] ->
        complete_probe({:error, :spawn_failed}, %{state | active: active})
    end
  end

  defp complete_probe(result, %{active: active} = state) do
    if active.probe_timer, do: Process.cancel_timer(active.probe_timer)

    {agent, steps} =
      case result do
        {:ok, output, code} -> Metadata.consume(active.agent, active.step, output, code)
        {:error, reason} -> {Metadata.failure(active.agent, active.step, reason), []}
      end

    advance(%{
      state
      | active: %{
          active
          | agent: agent,
            steps: steps ++ active.steps,
            port: nil,
            probe_timer: nil,
            output: ""
        }
    })
  end

  defp finish(result, %{active: active} = state) do
    cleanup(active)
    GenServer.reply(active.from, result)
    {:noreply, %{state | active: nil}}
  end

  defp cleanup(active) do
    stop_child(active.port)
    if active.probe_timer, do: Process.cancel_timer(active.probe_timer)
    Process.cancel_timer(active.scan_timer)
    Process.demonitor(active.monitor, [:flush])
    File.rm_rf(active.directory)
    :ok
  end

  defp stop_child(nil), do: :ok

  defp stop_child(port) do
    # The port still owns this PID; never signal a cached PID after closing it.
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        System.cmd("/bin/kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
        if Port.info(port), do: Port.close(port)

      nil ->
        :ok
    end
  rescue
    _ in ArgumentError -> :ok
  end

  defp limit(opts, key, maximum) do
    value = Keyword.get(opts, key, maximum)

    if is_integer(value) and value > 0 and value <= maximum,
      do: value,
      else: raise(ArgumentError, "invalid probe limit")
  end
end
