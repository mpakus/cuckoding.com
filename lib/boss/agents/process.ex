defmodule Boss.Agents.Process do
  @moduledoc "Bounded byte transport and owned process-group cleanup on macOS."

  @doc """
  Runs a command without a shell. Send `:stop` to the caller to cancel it.

  The callback runs in a separate persistent worker and receives `{:started, pid}`,
  `{:stdout, bytes}` and `{:stderr, bytes}`. It must return `:ok`; `:stop` cancels,
  any other result fails. A successful return waits for every callback.
  Cleanup covers the owned process group, never arbitrary detached sessions.
  """
  def run(executable, args, opts) do
    cond do
      :os.type() != {:unix, :darwin} ->
        failure(:unsupported)

      not valid?(executable, args, opts) ->
        failure(:invalid_options)

      true ->
        caller = self()
        ref = make_ref()
        {owner, monitor} = spawn_monitor(fn -> own(caller, ref, executable, args, opts) end)
        await(owner, monitor, ref)
    end
  end

  defp await(owner, monitor, ref) do
    receive do
      {^ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^owner, _} ->
        failure(:owner_lost)

      :stop ->
        send(owner, :stop)
        await(owner, monitor, ref)
    end
  end

  defp own(caller, ref, executable, args, opts) do
    Process.flag(:trap_exit, true)
    caller_monitor = Process.monitor(caller)

    result =
      try do
        execute(caller_monitor, executable, args, opts)
      rescue
        _ -> failure(:start_failed)
      catch
        _, _ -> failure(:start_failed)
      end

    send(caller, {ref, result})
  end

  defp execute(caller_monitor, executable, args, opts) do
    timeout = Keyword.get(opts, :timeout_ms, 60_000)
    limit = Keyword.get(opts, :output_limit, 8_388_608)
    native_args = [Integer.to_string(timeout), Integer.to_string(limit), executable | args]

    environment =
      Enum.map(Keyword.get(opts, :env, []), fn {key, value} ->
        {String.to_charlist(key), if(is_nil(value), do: false, else: String.to_charlist(value))}
      end)

    port =
      Port.open({:spawn_executable, guardian()}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        {:packet, 4},
        {:args, native_args},
        {:cd, Keyword.fetch!(opts, :cd)},
        {:env, environment}
      ])

    owner = self()
    callback_ref = make_ref()
    callback = Keyword.get(opts, :on_event, fn _ -> :ok end)
    consumer = spawn_link(fn -> consume(owner, callback_ref, callback) end)

    try do
      true = Port.command(port, ["I", Keyword.get(opts, :input, "")], [:nosuspend])

      loop(%{
        port: port,
        consumer: consumer,
        callback_ref: callback_ref,
        caller_monitor: caller_monitor,
        pending: %{},
        receipt: nil,
        helper_exit: nil,
        cause: nil,
        reason: nil,
        deadline: now() + timeout + 1000,
        eof: %{stdout: false, stderr: false},
        exit_kind: nil,
        exit_code: nil,
        signal: nil,
        stdout_bytes: 0,
        stderr_bytes: 0
      })
    after
      Process.unlink(consumer)
      Process.exit(consumer, :kill)

      try do
        Port.close(port)
      rescue
        ArgumentError -> :ok
      end
    end
  end

  defp guardian, do: Application.app_dir(:boss, "priv/native/boss_guardian")

  defp consume(owner, token, callback) do
    receive do
      {^token, ref, event} ->
        result =
          try do
            case callback.(event) do
              :ok -> :ok
              :stop -> :stop
              _ -> :failed
            end
          rescue
            _ -> :failed
          catch
            _, _ -> :failed
          end

        send(owner, {token, ref, result})
        if result == :ok, do: consume(owner, token, callback)
    end
  end

  defp loop(state) do
    state = check_deadline(state)

    cond do
      state.helper_exit != nil and state.receipt == nil ->
        finish(state, :unknown, :helper_lost)

      state.helper_exit != nil and map_size(state.pending) == 0 ->
        finish(state, state.receipt.cleanup, state.receipt.reason)

      state.cause != nil and now() >= state.deadline ->
        finish(state, :unknown, :cleanup_timeout)

      true ->
        receive do
          {port, {:data, packet}} when port == state.port ->
            loop(packet(state, packet))

          {port, {:exit_status, status}} when port == state.port ->
            loop(%{state | helper_exit: status})

          {token, ref, result} when token == state.callback_ref ->
            loop(acknowledge(state, ref, result))

          :stop ->
            loop(stop(state, :cancelled, :stopped))

          {:DOWN, monitor, :process, _, _} when monitor == state.caller_monitor ->
            loop(stop(state, :cancelled, :owner_down))

          {:EXIT, consumer, _} when consumer == state.consumer ->
            loop(stop(state, :failed, :consumer_failed))

          {:EXIT, port, :normal} when port == state.port ->
            loop(state)

          {:EXIT, port, _} when port == state.port ->
            finish(state, :unknown, :helper_lost)
        after
          max(0, min(20, state.deadline - now())) -> loop(state)
        end
    end
  end

  defp packet(state, <<?S, pid::unsigned-big-32>>) when pid > 0,
    do: dispatch(state, :started, {:started, pid})

  defp packet(state, <<stream, bytes::binary>>)
       when stream in [?O, ?E] and byte_size(bytes) in 1..4096 do
    {name, counter} =
      if stream == ?O, do: {:stdout, :stdout_bytes}, else: {:stderr, :stderr_bytes}

    state = Map.update!(state, counter, &(&1 + byte_size(bytes)))
    dispatch(state, stream, {name, bytes})
  end

  defp packet(state, <<?F, stream>>) when stream in [?O, ?E] do
    name = if stream == ?O, do: :stdout, else: :stderr
    %{state | eof: Map.put(state.eof, name, true)}
  end

  defp packet(state, <<?X, kind, code::unsigned-big-32>>) when kind in [?e, ?s],
    do: exit_result(state, kind, code)

  defp packet(state, <<?D, cause, cleanup, eof, kind, code::unsigned-big-32>>)
       when cause in 0..5 and cleanup in 0..1 and eof in 0..3 and kind in [0, ?e, ?s] do
    {outcome, reason} =
      case cause do
        0 -> {:exited, nil}
        1 -> {:cancelled, :stopped}
        2 -> {:timeout, :timeout}
        3 -> {:output_limit, :output_limit}
        4 -> {:failed, :process_failed}
        5 -> {:failed, :lingering_processes}
      end

    state = exit_result(state, kind, code)
    receipt = %{cleanup: if(cleanup == 1, do: :group_empty, else: :unknown), reason: reason}

    state = %{
      state
      | receipt: receipt,
        eof: %{stdout: Bitwise.band(eof, 1) != 0, stderr: Bitwise.band(eof, 2) != 0}
    }

    if outcome == :exited, do: state, else: stop(state, outcome, reason)
  end

  defp packet(state, _), do: stop(state, :failed, :invalid_protocol)

  defp dispatch(%{cause: cause} = state, stream, _) when cause != nil do
    credit(state.port, stream)
    state
  end

  defp dispatch(state, stream, event) do
    if stream in Map.values(state.pending) do
      stop(state, :failed, :invalid_protocol)
    else
      ref = make_ref()
      send(state.consumer, {state.callback_ref, ref, event})
      %{state | pending: Map.put(state.pending, ref, stream)}
    end
  end

  defp acknowledge(state, ref, :ok) do
    case Map.pop(state.pending, ref) do
      {nil, _} ->
        state

      {stream, pending} ->
        credit(state.port, stream)
        %{state | pending: pending}
    end
  end

  defp acknowledge(state, _, :stop), do: stop(state, :cancelled, :consumer_stopped)
  defp acknowledge(state, _, _), do: stop(state, :failed, :consumer_failed)

  defp exit_result(state, ?e, code), do: %{state | exit_kind: :exit, exit_code: code, signal: nil}

  defp exit_result(state, ?s, signal),
    do: %{state | exit_kind: :signal, exit_code: nil, signal: signal}

  defp exit_result(state, 0, _), do: state

  defp credit(port, stream) when stream in [?O, ?E], do: command(port, <<?A, stream>>)
  defp credit(_, _), do: :ok

  defp command(port, data) do
    Port.command(port, data, [:nosuspend])
  rescue
    ArgumentError -> false
  end

  defp stop(%{cause: cause} = state, _, _) when cause != nil, do: state

  defp stop(state, cause, reason) do
    Process.unlink(state.consumer)
    Process.exit(state.consumer, :kill)
    command(state.port, <<?Q>>)
    %{state | cause: cause, reason: reason, pending: %{}, deadline: now() + 3000}
  end

  defp check_deadline(%{cause: nil} = state) do
    if now() >= state.deadline, do: stop(state, :timeout, :timeout), else: state
  end

  defp check_deadline(state), do: state

  defp finish(state, cleanup, reason) do
    complete =
      state.eof.stdout && state.eof.stderr && state.exit_kind != nil && cleanup == :group_empty &&
        state.helper_exit == 0

    outcome = state.cause || if(complete, do: :exited, else: :failed)
    reason = state.reason || reason || if(complete, do: nil, else: :incomplete)

    state
    |> Map.take([:exit_kind, :exit_code, :signal, :eof, :stdout_bytes, :stderr_bytes])
    |> Map.merge(%{outcome: outcome, cleanup: cleanup, reason: reason})
  end

  defp failure(reason),
    do: %{
      outcome: if(reason == :unsupported, do: :unsupported, else: :failed),
      reason: reason,
      cleanup: :unknown,
      eof: %{stdout: false, stderr: false},
      exit_kind: nil,
      exit_code: nil,
      signal: nil,
      stdout_bytes: 0,
      stderr_bytes: 0
    }

  defp valid?(executable, args, opts) do
    is_list(opts) && Keyword.keyword?(opts) && text?(executable, 4096) &&
      Path.type(executable) == :absolute &&
      is_list(args) && length(args) <= 128 && Enum.all?(args, &text?(&1, 16_384)) &&
      text?(opts[:cd], 4096) && Path.type(opts[:cd]) == :absolute &&
      is_binary(Keyword.get(opts, :input, "")) &&
      byte_size(Keyword.get(opts, :input, "")) <= 1_048_576 &&
      Keyword.get(opts, :timeout_ms, 60_000) in 1..86_400_000 &&
      Keyword.get(opts, :output_limit, 8_388_608) in 1..67_108_864 &&
      is_function(Keyword.get(opts, :on_event, fn _ -> :ok end), 1) &&
      is_list(Keyword.get(opts, :env, [])) &&
      Enum.all?(Keyword.get(opts, :env, []), &environment?/1)
  end

  defp text?(text, limit),
    do:
      is_binary(text) && byte_size(text) <= limit && String.valid?(text) &&
        not String.contains?(text, <<0>>)

  defp environment?({key, value}),
    do:
      text?(key, 256) && key != "" && not String.contains?(key, "=") &&
        (is_nil(value) || text?(value, 131_072))

  defp environment?(_), do: false
  defp now, do: System.monotonic_time(:millisecond)
end
