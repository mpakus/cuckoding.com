Mix.install([{:erlexec, "2.5.0"}])

defmodule BossRunnerSpike do
  @moduledoc "Experimental process probe, not the BOSS production runner."

  def run(argv, opts \\ []) do
    trapping = Process.flag(:trap_exit, true)

    try do
      # Direct argv avoids shell interpolation; group 0 creates an owned group.
      native = [:stdout, :stderr, :kill_group, {:group, 0}, {:kill_timeout, 1}]
      native = if opts[:cd], do: [{:cd, opts[:cd]} | native], else: native

      case :exec.run_link(argv, native) do
        {:ok, pid, os_pid} ->
          now = now()

          loop(%{
            pid: pid,
            os_pid: os_pid,
            buffer: "",
            max_buffer: 0,
            stdout_bytes: 0,
            stderr_bytes: 0,
            stderr: "",
            events: 0,
            event_types: %{},
            completed: false,
            failed: false,
            cause: nil,
            exit: nil,
            deadline: now + Keyword.get(opts, :timeout, 5_000),
            last_output: now,
            idle_timeout: Keyword.get(opts, :idle_timeout, 2_000),
            line_limit: Keyword.get(opts, :line_limit, 16_384),
            output_limit: Keyword.get(opts, :output_limit, 1_048_576),
            event_limit: Keyword.get(opts, :event_limit, 1_024)
          })

        {:error, reason} ->
          %{outcome: :spawn_failed, error: inspect(reason)}
      end
    after
      Process.flag(:trap_exit, trapping)
    end
  end

  defp loop(state) do
    state = check_deadline(state)
    wait = max(0, min(state.deadline, state.last_output + state.idle_timeout) - now())

    receive do
      {stream, os_pid, data} when stream in [:stdout, :stderr] and os_pid == state.os_pid ->
        state |> output(stream, data) |> loop()

      {:EXIT, pid, reason} when pid == state.pid ->
        exit =
          case reason do
            :normal -> {:status, 0}
            {:exit_status, status} -> :exec.status(status)
            other -> {:unknown, other}
          end

        finish(%{state | exit: exit})

      :cancel ->
        state |> stop(:cancelled) |> loop()
    after
      wait ->
        if state.cause && now() >= state.deadline do
          finish(%{state | exit: {:unknown, :cleanup_timeout}})
        else
          loop(state)
        end
    end
  end

  defp check_deadline(%{cause: cause} = state) when not is_nil(cause), do: state

  defp check_deadline(state) do
    cond do
      now() >= state.deadline -> stop(state, :timeout)
      now() >= state.last_output + state.idle_timeout -> stop(state, :idle_timeout)
      true -> state
    end
  end

  defp stop(%{cause: cause} = state, _) when not is_nil(cause), do: state

  defp stop(state, cause) do
    # erlexec reports requested stops as exit zero; the cause must win.
    :exec.stop(state.pid)
    %{state | cause: cause, deadline: now() + 2_500, last_output: now(), idle_timeout: 2_500}
  end

  defp output(%{cause: cause} = state, _, _) when not is_nil(cause), do: state

  defp output(state, stream, data) do
    key = if stream == :stdout, do: :stdout_bytes, else: :stderr_bytes
    state = %{state | key => state[key] + byte_size(data), last_output: now()}

    cond do
      state.stdout_bytes + state.stderr_bytes > state.output_limit ->
        stop(state, :output_limit)

      stream == :stderr ->
        keep = min(byte_size(data), 1_024 - byte_size(state.stderr))
        %{state | stderr: state.stderr <> binary_part(data, 0, keep)}

      true ->
        lines(state, data)
    end
  end

  defp lines(state, data) do
    [part | rest] = :binary.split(data, "\n")
    size = byte_size(state.buffer) + byte_size(part)

    if size > state.line_limit do
      stop(state, :line_limit)
    else
      state = %{state | buffer: state.buffer <> part, max_buffer: max(state.max_buffer, size)}

      case rest do
        [] ->
          state

        [tail] ->
          state = event(state)
          if state.cause, do: state, else: lines(%{state | buffer: ""}, tail)
      end
    end
  end

  defp event(state) do
    case JSON.decode(state.buffer) do
      {:ok, %{"type" => type}} when is_binary(type) and byte_size(type) > 0 ->
        if state.events >= state.event_limit do
          stop(state, :event_limit)
        else
          %{
            state
            | events: state.events + 1,
              event_types: Map.update(state.event_types, type, 1, &(&1 + 1)),
              completed: state.completed or type == "turn.completed",
              failed: state.failed or type in ["turn.failed", "error"]
          }
        end

      {:ok, _} ->
        stop(state, :invalid_event)

      {:error, _} ->
        stop(state, :invalid_json)
    end
  end

  defp finish(state) do
    outcome =
      cond do
        state.cause -> state.cause
        state.exit != {:status, 0} -> :process_failed
        state.buffer != "" -> :unterminated_jsonl
        state.failed -> :protocol_failed
        state.completed -> :completed
        true -> :missing_terminal
      end

    Map.take(state, [
      :os_pid,
      :exit,
      :events,
      :event_types,
      :stdout_bytes,
      :stderr_bytes,
      :stderr,
      :max_buffer
    ])
    |> Map.put(:outcome, outcome)
  end

  defp now, do: System.monotonic_time(:millisecond)
end
