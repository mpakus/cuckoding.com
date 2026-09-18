defmodule Cuckoding.Execution.LocalProcessRunner do
  @moduledoc "Host runner with explicit process groups, environment scrubbing, and bounded output."
  @behaviour Cuckoding.Execution.RunnerBridge

  import Ecto.Query

  alias Cuckoding.Execution
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.LocalProcessWorker
  alias Cuckoding.Execution.ProcessRecord
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Repo

  defmodule Handle do
    @moduledoc false
    defstruct [:worker, :process]
  end

  @impl true
  def prepare(%Environment{} = environment, _options) do
    with :ok <- directory?(environment.run_dir),
         :ok <- directory?(environment.worktree_path),
         :ok <- File.mkdir_p(Path.join(environment.run_dir, "artifacts")),
         :ok <- File.mkdir_p(Path.join([environment.run_dir, "agent", "home"])) do
      {:ok, environment}
    end
  end

  @impl true
  def start(%Environment{} = environment, command, options \\ []) when is_map(command) do
    child = {LocalProcessWorker, {environment, command, options}}

    with {:ok, worker} <- DynamicSupervisor.start_child(Cuckoding.Execution.ProcessWorkers, child),
         {:ok, process} <- LocalProcessWorker.process(worker) do
      {:ok, %Handle{worker: worker, process: process}}
    end
  end

  @impl true
  def exec(%Environment{} = environment, command, options \\ []) do
    with {:ok, handle} <- start(environment, command, options),
         do: LocalProcessWorker.await(handle.worker)
  end

  @impl true
  def pause(%Environment{} = environment, _options \\ []) do
    with :ok <- verify_owned_processes(environment), do: {:ok, environment}
  end

  @impl true
  def hibernate(%Environment{} = environment, options \\ []), do: destroy(environment, options)

  @impl true
  def resume(%Environment{} = environment, options \\ []), do: prepare(environment, options)

  @impl true
  def inspect(%ProcessRecord{} = process, _options \\ []) do
    Cuckoding.Execution.LocalHostInspector.inspect_process(process)
  end

  @impl true
  def stream_events(%ProcessRecord{} = process, _options \\ []) do
    environment = Repo.get!(Environment, process.environment_id)

    events =
      Repo.all(
        from(event in RunEvent,
          where:
            event.run_id == ^environment.run_id and
              fragment("json_extract(?, '$.process_id')", event.payload) == ^process.id,
          order_by: event.sequence
        )
      )

    {:ok, events}
  end

  @impl true
  def destroy(%Environment{} = environment, options \\ []) do
    Repo.all(
      from(process in ProcessRecord,
        where: process.environment_id == ^environment.id and process.state == "running"
      )
    )
    |> Enum.reduce_while(:ok, fn process, :ok ->
      case terminate_process(process, options) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def stop(%Handle{} = handle), do: LocalProcessWorker.stop(handle.worker)
  def result(%Handle{} = handle), do: LocalProcessWorker.await(handle.worker)

  defp terminate_process(process, options) do
    case Registry.lookup(Cuckoding.RunRegistry, {:process, process.id}) do
      [{worker, _value}] ->
        with {:ok, _result} <- LocalProcessWorker.stop(worker), do: :ok

      [] ->
        environment = Repo.get!(Environment, process.environment_id)

        before_signal = fn signal, pgids ->
          {:ok, _result} =
            EventStore.append(environment.run_id, %{
              event_type: "process.signal",
              public_summary: "Sent #{signal} to owned process groups",
              payload: %{"process_id" => process.id, "signal" => signal, "pgids" => pgids}
            })

          :ok
        end

        with {:ok, _steps} <-
               Cuckoding.Execution.ProcessTerminator.terminate(
                 process,
                 Keyword.put(options, :before_signal, before_signal)
               ),
             {:ok, _finished} <-
               Execution.finish_process(process, -1, Cuckoding.Clock.wall_now()) do
          :ok
        end
    end
  end

  defp verify_owned_processes(environment) do
    Repo.all(
      from(process in ProcessRecord,
        where: process.environment_id == ^environment.id and process.state == "running"
      )
    )
    |> Enum.reduce_while(:ok, fn process, :ok ->
      case Cuckoding.Execution.LocalHostInspector.inspect_process(process) do
        {:ok, %{status: :matching}} -> {:cont, :ok}
        {:ok, %{status: status}} -> {:halt, {:error, {:process_ownership_unverified, status}}}
        {:error, reason} -> {:halt, {:error, {:process_ownership_unverified, reason}}}
      end
    end)
  end

  defp directory?(path) do
    case File.stat(path) do
      {:ok, %{type: :directory}} -> :ok
      _other -> {:error, :missing_directory}
    end
  end
end

defmodule Cuckoding.Execution.LocalProcessWorker do
  @moduledoc false
  use GenServer, restart: :temporary

  alias Cuckoding.Execution
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.ProcessTerminator
  alias Cuckoding.Identifier
  alias Cuckoding.Repo
  alias Cuckoding.Security.Redactor

  @ruby "/usr/bin/ruby"
  @shim "STDIN.reopen(File::NULL); STDOUT.sync=true; STDERR.reopen(STDOUT); sleep 0.05; exec(*ARGV)"
  @safe_path "/usr/bin:/bin:/usr/sbin:/sbin"
  @base_keys ~w(PATH HOME LANG LC_ALL TZ PORT)
  @sensitive ~r/(AUTH|COOKIE|CREDENTIAL|KEY|PASSWORD|SECRET|TOKEN)/i

  def start_link(arguments), do: GenServer.start_link(__MODULE__, arguments)
  def process(worker), do: GenServer.call(worker, :process)
  def await(worker), do: GenServer.call(worker, :await, :infinity)
  def stop(worker), do: GenServer.call(worker, :stop, :infinity)

  @impl true
  def init({environment, command, options}) do
    Process.flag(:trap_exit, true)

    with {:ok, executable, args, role} <- command(command),
         {:ok, child_env} <-
           child_environment(environment, Keyword.get(options, :env, %{}), options),
         {:ok, artifact, file} <- artifact(environment, Identifier.generate()),
         {:ok, port, pid} <- spawn(executable, args, environment.worktree_path, child_env),
         {:ok, pgid, identity} <- ProcessTerminator.await_identity(pid),
         {:ok, process} <-
           Execution.record_process(%{
             environment_id: environment.id,
             agent_session_id: command[:agent_session_id],
             command_id: command[:command_id],
             pid: pid,
             pgid: pgid,
             start_identity: identity,
             role: role
           }) do
      {:ok, _owner} = Registry.register(Cuckoding.RunRegistry, {:process, process.id}, nil)

      record_event(environment.run_id, process.id, "process.started", "Process group started", %{
        "pid" => pid,
        "pgid" => pgid,
        "role" => role
      })

      timeout = Keyword.get(options, :timeout, 60_000)

      timer =
        if timeout == :infinity, do: nil, else: Process.send_after(self(), :timeout, timeout)

      {:ok,
       %{
         port: port,
         process: process,
         environment: environment,
         artifact: artifact,
         file: file,
         preview: "",
         output_bytes: 0,
         output_limit: Keyword.get(options, :output_limit, 1_048_576),
         truncated?: false,
         secrets: Keyword.get(options, :redact, []),
         waiter: nil,
         timer: timer,
         timed_out?: false,
         result: nil,
         grace_ms: Keyword.get(options, :termination_grace_ms, 2_000)
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:process, _from, state), do: {:reply, {:ok, state.process}, state}

  def handle_call(:await, _from, %{result: result} = state) when not is_nil(result),
    do: {:stop, :normal, {:ok, result}, state}

  def handle_call(:await, from, state), do: {:noreply, %{state | waiter: from}}

  def handle_call(:stop, from, %{result: nil} = state) do
    state = %{state | waiter: from}
    {:noreply, begin_termination(state, false)}
  end

  def handle_call(:stop, _from, state), do: {:stop, :normal, {:ok, state.result}, state}

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    safe = Redactor.redact(data, state.secrets)
    :ok = IO.binwrite(state.file, safe)
    {:noreply, capture_preview(state, safe)}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    File.close(state.file)

    result = %{
      process: state.process,
      exit_status: status,
      output: state.preview,
      output_bytes: state.output_bytes,
      truncated?: state.truncated?,
      artifact_path: state.artifact,
      artifact_sha256: sha256(state.artifact),
      timed_out?: state.timed_out?
    }

    {:ok, finished} = Execution.finish_process(state.process, status, Cuckoding.Clock.wall_now())

    record_event(
      state.environment.run_id,
      finished.id,
      "process.exited",
      "Process group exited",
      %{"exit_status" => status, "timed_out" => state.timed_out?}
    )

    waiter = state.waiter
    state = %{state | process: finished, result: %{result | process: finished}, waiter: nil}

    if waiter do
      GenServer.reply(waiter, {:ok, state.result})
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:timeout, %{result: nil} = state),
    do: {:noreply, begin_termination(state, true)}

  def handle_info(:timeout, state), do: {:noreply, state}
  def handle_info({:EXIT, _port, :normal}, state), do: {:noreply, state}

  defp begin_termination(state, timed_out?) do
    if timed_out? do
      record_event(
        state.environment.run_id,
        state.process.id,
        "process.timeout",
        "Process exceeded its timeout",
        %{}
      )
    end

    event = fn signal, pgids ->
      record_event(
        state.environment.run_id,
        state.process.id,
        "process.signal",
        "Sent #{signal} to owned process groups",
        %{"signal" => signal, "pgids" => pgids}
      )
    end

    case ProcessTerminator.terminate(state.process,
           grace_ms: state.grace_ms,
           before_signal: event
         ) do
      {:ok, _steps} ->
        %{state | timed_out?: timed_out? or state.timed_out?}

      {:error, reason} ->
        if state.waiter, do: GenServer.reply(state.waiter, {:error, reason})
        %{state | waiter: nil}
    end
  end

  defp capture_preview(state, data) do
    remaining = max(state.output_limit - byte_size(state.preview), 0)
    kept = if byte_size(data) <= remaining, do: data, else: binary_part(data, 0, remaining)
    truncated? = state.truncated? or byte_size(data) > remaining

    if truncated? and not state.truncated? do
      record_event(
        state.environment.run_id,
        state.process.id,
        "process.output_truncated",
        "Process output preview was truncated; full redacted output is in the artifact",
        %{"limit_bytes" => state.output_limit}
      )
    end

    %{
      state
      | preview: state.preview <> kept,
        output_bytes: state.output_bytes + byte_size(data),
        truncated?: truncated?
    }
  end

  defp child_environment(environment, requested, options) when is_map(requested) do
    allowed = @base_keys ++ Keyword.get(options, :environment_allowlist, [])

    with :ok <- validate_environment(requested, allowed) do
      home = Path.join([environment.run_dir, "agent", "home"])

      {:ok,
       %{"PATH" => @safe_path, "HOME" => home, "LANG" => "en_US.UTF-8", "TZ" => "UTC"}
       |> Map.merge(requested)}
    end
  end

  defp child_environment(_environment, _requested, _options),
    do: {:error, :invalid_environment}

  defp validate_environment(environment, allowed) do
    Enum.find_value(environment, :ok, fn {key, value} ->
      cond do
        not is_binary(key) or not is_binary(value) -> {:error, :invalid_environment}
        Regex.match?(@sensitive, key) -> {:error, {:sensitive_environment_key, key}}
        key in allowed or String.starts_with?(key, "CUCKODING_") -> false
        true -> {:error, {:environment_key_not_allowed, key}}
      end
    end)
  end

  defp command(%{executable: executable} = command) when is_binary(executable) do
    args = Map.get(command, :args, [])
    role = Map.get(command, :role, "command")

    cond do
      Path.type(executable) != :absolute -> {:error, :executable_must_be_absolute}
      not File.exists?(executable) -> {:error, :executable_not_found}
      not is_list(args) or not Enum.all?(args, &is_binary/1) -> {:error, :invalid_arguments}
      not is_binary(role) -> {:error, :invalid_role}
      true -> {:ok, executable, args, role}
    end
  end

  defp command(_command), do: {:error, :invalid_command}

  defp artifact(environment, id) do
    path = Path.join([environment.run_dir, "artifacts", "process-#{id}.log"])

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, file} <- File.open(path, [:write, :binary]),
         :ok <- File.chmod(path, 0o600) do
      {:ok, path, file}
    end
  end

  defp spawn(executable, args, cwd, environment) do
    inherited_unsets =
      Enum.map(System.get_env(), fn {key, _value} -> {to_charlist(key), false} end)

    allowed = Enum.map(environment, fn {key, value} -> {to_charlist(key), to_charlist(value)} end)

    port =
      Port.open({:spawn_executable, @ruby}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        :hide,
        {:cd, cwd},
        {:env, inherited_unsets ++ allowed},
        {:args, ["-e", @shim, "--", executable | args]}
      ])

    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> {:ok, port, pid}
      nil -> {:error, :process_start_failed}
    end
  end

  defp record_event(run_id, process_id, type, summary, payload) do
    {:ok, _result} =
      EventStore.append(run_id, %{
        event_type: type,
        public_summary: summary,
        payload: Map.put(payload, "process_id", process_id)
      })

    :ok
  end

  defp sha256(path) do
    path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end
end

defmodule Cuckoding.Execution.ProcessTerminator do
  @moduledoc false

  alias Cuckoding.Execution.LocalHostInspector

  @signals ["INT", "TERM", "KILL"]

  def await_identity(pid, attempts \\ 100)

  def await_identity(_pid, 0), do: {:error, :process_identity_unavailable}

  def await_identity(pid, attempts) do
    with {:ok, identity} <- LocalHostInspector.process_identity(pid, []),
         {:ok, pgid} <- LocalHostInspector.process_group(pid),
         true <- pgid == pid do
      {:ok, pgid, identity}
    else
      _other ->
        Process.sleep(10)
        await_identity(pid, attempts - 1)
    end
  end

  def terminate(process, options \\ []) do
    with {:ok, identity} <- LocalHostInspector.process_identity(process.pid, []),
         true <- identity == process.start_identity do
      pgids = LocalHostInspector.owned_process_groups(process.pid, process.pgid)
      grace_ms = Keyword.get(options, :grace_ms, 2_000)
      before_signal = Keyword.get(options, :before_signal, fn _signal, _pgids -> :ok end)
      signal_ladder(pgids, grace_ms, before_signal, [])
    else
      :gone ->
        if LocalHostInspector.groups_empty?([process.pgid]),
          do: {:ok, []},
          else: {:error, :process_identity_unavailable}

      false ->
        {:error, :process_identity_mismatch}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp signal_ladder(pgids, _grace_ms, _before_signal, steps)
       when length(steps) == length(@signals) do
    if LocalHostInspector.groups_empty?(pgids),
      do: {:ok, Enum.reverse(steps)},
      else: {:error, :termination_failed}
  end

  defp signal_ladder(pgids, grace_ms, before_signal, steps) do
    if LocalHostInspector.groups_empty?(pgids) do
      {:ok, Enum.reverse(steps)}
    else
      signal = Enum.at(@signals, length(steps))
      :ok = before_signal.(signal, pgids)

      case signal_groups(pgids, signal) do
        :ok ->
          Process.sleep(grace_ms)
          signal_ladder(pgids, grace_ms, before_signal, [signal | steps])

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp signal_groups(pgids, signal) do
    Enum.reduce_while(pgids, :ok, fn pgid, :ok ->
      case System.cmd("/bin/kill", ["-s", signal, "--", "-#{pgid}"], stderr_to_stdout: true) do
        {_output, 0} -> {:cont, :ok}
        {output, _status} -> {:halt, {:error, {:signal_failed, signal, String.trim(output)}}}
      end
    end)
  end
end

defmodule Cuckoding.Execution.LocalHostInspector do
  @moduledoc false
  @behaviour Cuckoding.Execution.RecoveryInspector

  alias Cuckoding.Execution.GitRecoveryInspector

  @impl true
  def process_identity(pid, _options) do
    case System.cmd("/bin/ps", ["-p", Integer.to_string(pid), "-o", "lstart="],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, String.trim(output)}
      {_output, 1} -> :gone
      {_output, _status} -> {:error, :process_inspection_failed}
    end
  end

  @impl true
  def port_owner(port, _options) when is_integer(port) and port in 1_024..65_535 do
    case System.cmd(
           "/usr/sbin/lsof",
           ["-nP", "-a", "-iTCP:#{port}", "-sTCP:LISTEN", "-Fp"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> listener_owner(output)
      {_output, 1} -> :free
      {_output, _status} -> {:error, :port_inspection_failed}
    end
  end

  def port_owner(_port, _options), do: {:error, :invalid_port}

  @impl true
  def worktree_status(environment, options),
    do: GitRecoveryInspector.worktree_status(environment, options)

  def process_group(pid) do
    case System.cmd("/bin/ps", ["-p", Integer.to_string(pid), "-o", "pgid="],
           stderr_to_stdout: true
         ) do
      {output, 0} -> Integer.parse(String.trim(output)) |> parsed_integer()
      {_output, 1} -> :gone
      {_output, _status} -> {:error, :process_inspection_failed}
    end
  end

  def inspect_process(process) do
    case process_identity(process.pid, []) do
      {:ok, identity} when identity == process.start_identity ->
        rows = process_rows()
        pgids = owned_process_groups(process.pid, process.pgid)
        members = Enum.filter(rows, &(&1.pgid in pgids))

        {:ok,
         %{
           status: :matching,
           process_count: length(members),
           memory_bytes: Enum.sum(Enum.map(members, & &1.rss_kb)) * 1_024,
           pgids: pgids
         }}

      {:ok, _identity} ->
        {:error, :process_identity_mismatch}

      :gone ->
        {:ok, %{status: :gone, process_count: 0, memory_bytes: 0, pgids: []}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def owned_process_groups(root_pid, root_pgid) do
    rows = process_rows()

    rows
    |> descendants(root_pid)
    |> Enum.map(& &1.pgid)
    |> Enum.reject(&(&1 == root_pgid))
    |> Enum.uniq()
    |> Kernel.++([root_pgid])
  end

  def groups_empty?(pgids) do
    process_rows() |> Enum.all?(&(&1.pgid not in pgids))
  end

  defp listener_owner(output) do
    roots =
      output
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.starts_with?(&1, "p"))
      |> Enum.map(&String.trim_leading(&1, "p"))
      |> Enum.map(&Integer.parse/1)
      |> Enum.flat_map(fn
        {pid, ""} ->
          case process_group(pid) do
            {:ok, pgid} -> [pgid]
            _other -> []
          end

        _other ->
          []
      end)
      |> Enum.uniq()

    case roots do
      [pid] ->
        with {:ok, identity} <- process_identity(pid, []), do: {:ok, pid, identity}

      [] ->
        {:error, :port_owner_unverified}

      _many ->
        {:error, :multiple_port_owners}
    end
  end

  defp descendants(rows, root_pid) do
    descendants(rows, [root_pid], [])
  end

  defp descendants(rows, parents, found) do
    children =
      Enum.filter(
        rows,
        &(&1.ppid in parents and &1.pid not in Enum.map(found, fn row -> row.pid end))
      )

    if children == [],
      do: found,
      else: descendants(rows, Enum.map(children, & &1.pid), found ++ children)
  end

  defp process_rows do
    case System.cmd("/bin/ps", ["-axo", "pid=,ppid=,pgid=,rss="], stderr_to_stdout: true) do
      {output, 0} -> Enum.flat_map(String.split(output, "\n", trim: true), &parse_row/1)
      _error -> []
    end
  end

  defp parse_row(line) do
    case line |> String.split() |> Enum.map(&Integer.parse/1) do
      [{pid, ""}, {ppid, ""}, {pgid, ""}, {rss_kb, ""}] ->
        [%{pid: pid, ppid: ppid, pgid: pgid, rss_kb: rss_kb}]

      _other ->
        []
    end
  end

  defp parsed_integer({value, ""}), do: {:ok, value}
  defp parsed_integer(_other), do: {:error, :process_inspection_failed}
end
