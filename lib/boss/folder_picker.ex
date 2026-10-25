defmodule Boss.FolderPicker do
  @moduledoc "One native folder dialog at a time, owned by the requesting LiveView task."
  use GenServer

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def choose(kind, initial \\ nil, server \\ __MODULE__) when kind in [:repository, :specs],
    do: GenServer.call(server, {:choose, kind, initial}, :infinity)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       active: nil,
       timeout: Keyword.get(opts, :timeout, 120_000),
       command: Keyword.get(opts, :command, &command/2)
     }}
  end

  @impl true
  def handle_call({:choose, _, _}, _from, %{active: active} = state) when active != nil,
    do: {:reply, {:error, :busy}, state}

  def handle_call({:choose, kind, initial}, from, state) do
    with {:ok, executable, args, cancel_codes} <- state.command.(kind, initial) do
      port =
        Port.open({:spawn_executable, executable}, [:binary, :exit_status, :hide, args: args])

      monitor = Process.monitor(elem(from, 0))
      timer = Process.send_after(self(), {:timeout, port}, state.timeout)

      {:noreply,
       %{
         state
         | active: %{
             port: port,
             from: from,
             monitor: monitor,
             timer: timer,
             output: "",
             cancel_codes: cancel_codes
           }
       }}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  rescue
    _ in [ArgumentError, ErlangError] -> {:reply, {:error, :unavailable}, state}
  end

  @impl true
  def handle_info({port, {:data, chunk}}, %{active: %{port: port} = active} = state) do
    if byte_size(active.output) + byte_size(chunk) <= 8192 do
      {:noreply, %{state | active: %{active | output: active.output <> chunk}}}
    else
      stop_dialog(port)
      finish({:error, :failed}, state)
    end
  end

  def handle_info({port, {:exit_status, code}}, %{active: %{port: port} = active} = state) do
    result =
      cond do
        code == 0 -> selection(active.output)
        code in active.cancel_codes -> :cancelled
        code == 5 -> {:error, :timeout}
        true -> {:error, :failed}
      end

    finish(result, state)
  end

  def handle_info({:timeout, port}, %{active: %{port: port}} = state) do
    stop_dialog(port)
    finish({:error, :timeout}, state)
  end

  def handle_info(
        {:DOWN, monitor, :process, _, _},
        %{active: %{monitor: monitor, port: port}} = state
      ) do
    stop_dialog(port)
    finish(:cancelled, state)
  end

  def handle_info({:EXIT, port, reason}, %{active: %{port: port}} = state) when reason != :normal,
    do: finish({:error, :failed}, state)

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, %{active: %{port: port}}), do: stop_dialog(port)
  def terminate(_, _), do: :ok

  defp finish(result, %{active: active} = state) do
    Process.cancel_timer(active.timer)
    Process.demonitor(active.monitor, [:flush])
    GenServer.reply(active.from, result)
    {:noreply, %{state | active: nil}}
  end

  defp stop_dialog(port) do
    # Closing a Port alone can leave its OS process alive. Signal only this live port's child.
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

  defp selection(output) do
    path = String.replace_suffix(output, "\n", "")

    cond do
      path == "" ->
        :cancelled

      String.valid?(path) and byte_size(path) <= 4096 and
        not String.contains?(path, [<<0>>, "\n", "\r"]) and
        Path.type(path) == :absolute and File.dir?(path) ->
        {:ok, Path.expand(path)}

      true ->
        {:error, :failed}
    end
  end

  defp command(kind, initial) do
    title =
      if kind == :repository,
        do: "Choose a Git repository for BOSS",
        else: "Choose the specs folder for BOSS"

    initial = if is_binary(initial) and File.dir?(initial), do: initial, else: System.user_home!()

    case :os.type() do
      {:unix, :darwin} ->
        script = """
        on run argv
          try
            with timeout of 120 seconds
              activate
              return POSIX path of (choose folder with prompt (item 1 of argv) default location (POSIX file (item 2 of argv)))
            end timeout
          on error number -128
            return ""
          end try
        end run
        """

        {:ok, "/usr/bin/osascript", ["-e", script, title, initial], []}

      {:unix, :linux} ->
        if (System.get_env("DISPLAY") || System.get_env("WAYLAND_DISPLAY")) &&
             System.find_executable("zenity") do
          {:ok, System.find_executable("zenity"),
           [
             "--file-selection",
             "--directory",
             "--title=#{title}",
             "--filename=#{initial}/",
             "--timeout=120"
           ], [1]}
        else
          {:error, :unavailable}
        end

      _ ->
        {:error, :unavailable}
    end
  end
end
