Mix.install([{:exile, "0.15.0"}])

defmodule BossTransportSpike do
  @moduledoc "Demand/EOF experiment only; no process-tree or delivery guarantee."
  alias Exile.Process, as: Command

  def run(argv, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 4096)

    unless is_integer(chunk_size) and chunk_size in 1..4096,
      do: raise(ArgumentError, "chunk_size must be 1..4096")

    previous = Process.flag(:trap_exit, true)
    coordinator = self()
    owner = spawn_link(fn -> own_command(coordinator, argv, chunk_size) end)
    consumer = Keyword.get(opts, :consumer)
    monitor = if consumer, do: Process.monitor(consumer)

    state = %{
      owner: owner,
      process: nil,
      readers: [],
      consumer: consumer,
      monitor: monitor,
      observer: Keyword.get(opts, :observer),
      pending: %{},
      max_pending: 0,
      eof: %{stdout: false, stderr: false},
      exit_status: nil,
      cause: nil,
      cleanup_timeout: false,
      deadline: now() + Keyword.get(opts, :timeout, 3000),
      kill_at: nil,
      output_limit: Keyword.get(opts, :output_limit, 1_048_576),
      stdout_bytes: 0,
      stderr_bytes: 0,
      max_chunk: 0,
      stdout_hash: :crypto.hash_init(:sha256),
      stderr_hash: :crypto.hash_init(:sha256)
    }

    try do
      loop(state)
    after
      # Linked readers and Exile cannot outlive this experiment's owner worker.
      Process.unlink(owner)
      if Process.alive?(owner), do: Process.exit(owner, :kill)
      if monitor, do: Process.demonitor(monitor, [:flush])
      Process.flag(:trap_exit, previous)
    end
  end

  defp own_command(coordinator, argv, chunk_size) do
    {:ok, process} = Command.start_link(argv, stderr: :consume)
    {:ok, os_pid} = Command.os_pid(process)
    owner = self()

    readers =
      for stream <- [:stdout, :stderr] do
        reader =
          spawn_link(fn ->
            monitor = Process.monitor(owner)

            receive do
              :begin -> read_loop(coordinator, owner, process, stream, chunk_size, monitor)
              {:DOWN, ^monitor, :process, _, _} -> :ok
            end
          end)

        :ok = Command.change_pipe_owner(process, stream, reader)
        reader
      end

    send(coordinator, {:ready, owner, process, readers, os_pid})

    receive do
      :begin -> Enum.each(readers, &send(&1, :begin))
    end

    :ok = Command.close_stdin(process)
    exit_result = Command.await_exit(process, :infinity)
    send(coordinator, {:command_exit, owner, exit_result})

    # Exile terminates when its owner dies. Keep it alive for inherited pipe tails.
    receive do
      :release -> :ok
    end
  end

  defp read_loop(coordinator, owner, process, stream, size, monitor) do
    result = read(process, stream, size)

    receive do
      :stop -> close_reader(process, stream)
      {:DOWN, ^monitor, :process, _, _} -> :ok
    after
      0 ->
        case result do
          {:ok, bytes} ->
            ref = make_ref()
            send(coordinator, {:chunk, owner, self(), stream, ref, bytes})

            receive do
              {:ack, ^ref} -> read_loop(coordinator, owner, process, stream, size, monitor)
              :stop -> close_reader(process, stream)
              {:DOWN, ^monitor, :process, _, _} -> :ok
            end

          :eof ->
            send(coordinator, {:eof, owner, stream})
            close_reader(process, stream)

          {:error, _} ->
            send(coordinator, {:read_error, owner, stream})
        end
    end
  end

  # Keep catch outside the recursive reader so acknowledged reads remain tail calls.
  defp read(process, stream, size) do
    case stream do
      :stdout -> Command.read(process, size)
      :stderr -> Command.read_stderr(process, size)
    end
  catch
    :exit, _ -> {:error, :reader_closed}
  end

  defp close_reader(process, :stdout), do: Command.close_stdout(process)
  defp close_reader(process, :stderr), do: Command.close_stderr(process)

  defp loop(state) do
    # A busy mailbox must not postpone either runtime or cleanup deadlines.
    state = check_deadline(state)

    cond do
      state.cleanup_timeout ->
        finish(state)

      state.cause != nil and state.exit_status != nil ->
        finish(state)

      state.exit_status != nil and Enum.all?(state.eof, fn {_, value} -> value end) ->
        finish(state)

      true ->
        wait = max(0, min(state.deadline, state.kill_at || state.deadline) - now())

        receive do
          {:ready, owner, process, readers, os_pid} when owner == state.owner ->
            state = %{state | process: process, readers: readers}

            if state.observer,
              do:
                send(
                  state.observer,
                  {:transport_started, self(),
                   %{process: process, readers: readers, os_pid: os_pid}}
                )

            send(state.owner, :begin)
            loop(state)

          {:chunk, owner, reader, stream, ref, bytes} when owner == state.owner ->
            loop(chunk(state, reader, stream, ref, bytes))

          {:ack, ref} ->
            case Map.pop(state.pending, ref) do
              {nil, _} ->
                loop(state)

              {reader, pending} ->
                send(reader, {:ack, ref})
                loop(%{state | pending: pending})
            end

          {:eof, owner, stream} when owner == state.owner ->
            observe(state, {:eof, stream})
            loop(%{state | eof: Map.put(state.eof, stream, true)})

          {:command_exit, owner, {:ok, status}} when owner == state.owner ->
            observe(state, {:exit, status})
            loop(%{state | exit_status: status})

          {:command_exit, owner, _} when owner == state.owner ->
            loop(stop(state, :failed))

          {:read_error, owner, _} when owner == state.owner ->
            loop(stop(state, :failed))

          :stop ->
            loop(stop(state, :cancelled))

          {:DOWN, monitor, :process, _, _} when monitor == state.monitor ->
            loop(stop(state, :consumer_down))

          {:EXIT, owner, _} when owner == state.owner ->
            loop(stop(state, :failed))
        after
          wait -> loop(state)
        end
    end
  end

  defp chunk(%{cause: cause} = state, reader, _, _, _) when cause != nil do
    send(reader, :stop)
    state
  end

  defp chunk(state, reader, stream, ref, bytes) do
    {counter, digest} =
      case stream do
        :stdout -> {:stdout_bytes, :stdout_hash}
        :stderr -> {:stderr_bytes, :stderr_hash}
      end

    pending = Map.put(state.pending, ref, reader)

    state = %{
      state
      | counter => state[counter] + byte_size(bytes),
        digest => :crypto.hash_update(state[digest], bytes),
        max_chunk: max(state.max_chunk, byte_size(bytes)),
        pending: pending,
        max_pending: max(state.max_pending, map_size(pending))
    }

    cond do
      state.stdout_bytes + state.stderr_bytes > state.output_limit ->
        stop(state, :output_limit)

      state.consumer ->
        send(state.consumer, {:transport_chunk, self(), stream, ref, bytes})
        state

      true ->
        send(reader, {:ack, ref})
        %{state | pending: Map.delete(pending, ref)}
    end
  end

  defp check_deadline(state) do
    cond do
      now() >= state.deadline and state.cause == nil ->
        stop(state, :timeout)

      now() >= state.deadline ->
        %{state | cleanup_timeout: true}

      state.kill_at != nil and now() >= state.kill_at ->
        signal(state.process, :sigkill)
        %{state | kill_at: nil}

      true ->
        state
    end
  end

  defp stop(%{cause: cause} = state, _) when cause != nil, do: state

  defp stop(state, cause) do
    Enum.each(state.readers, &send(&1, :stop))
    signal(state.process, :sigterm)
    %{state | cause: cause, deadline: now() + 1000, kill_at: now() + 100}
  end

  defp signal(nil, _), do: :ok

  defp signal(process, signal) do
    Command.kill(process, signal)
  catch
    :exit, _ -> :ok
  end

  defp finish(state) do
    cleanup(state)

    state
    |> Map.take([:exit_status, :stdout_bytes, :stderr_bytes, :eof, :max_chunk, :max_pending])
    |> Map.merge(%{
      outcome: state.cause || :complete,
      cleanup: if(state.cleanup_timeout, do: :incomplete, else: :exit_observed),
      stdout_sha256: :crypto.hash_final(state.stdout_hash) |> Base.encode16(case: :lower),
      stderr_sha256: :crypto.hash_final(state.stderr_hash) |> Base.encode16(case: :lower)
    })
  end

  defp cleanup(state) do
    processes =
      [state.owner | state.readers] ++ if(state.process, do: [state.process.pid], else: [])

    monitors = Enum.map(processes, &Process.monitor/1)
    Process.unlink(state.owner)
    Process.exit(state.owner, :kill)

    Enum.each(monitors, fn ref ->
      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      after
        100 -> :ok
      end

      Process.demonitor(ref, [:flush])
    end)

    flush_owned(state.owner)
  end

  defp flush_owned(owner) do
    receive do
      message when is_tuple(message) and tuple_size(message) >= 2 and elem(message, 1) == owner ->
        flush_owned(owner)
    after
      0 -> :ok
    end
  end

  defp observe(%{observer: nil}, _), do: :ok
  defp observe(state, event), do: send(state.observer, {:transport_event, self(), event})
  defp now, do: System.monotonic_time(:millisecond)
end
