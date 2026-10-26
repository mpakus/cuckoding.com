Code.require_file("transport.exs", __DIR__)
ExUnit.start()

defmodule BossTransportSpikeTest do
  use ExUnit.Case, async: false

  setup_all do
    root = scratch("build")
    on_exit(fn -> File.rm_rf!(root) end)
    binary = Path.join(root, "fixture")

    {output, code} =
      System.cmd(
        "cc",
        ["-Wall", "-Wextra", "-Werror", "-O2", Path.join(__DIR__, "fixture.c"), "-o", binary],
        stderr_to_stdout: true
      )

    assert {output, code} == {"", 0}
    %{binary: binary}
  end

  setup do
    root = scratch("run")

    on_exit(fn ->
      # Only test fixture processes still identifying this exclusive root may be signalled.
      case File.read(Path.join(root, "pids")) do
        {:ok, pids} ->
          for pid <- String.split(pids) do
            {command, _} =
              System.cmd("/bin/ps", ["-p", pid, "-o", "command="], stderr_to_stdout: true)

            if String.contains?(command, root),
              do: System.cmd("/bin/kill", ["-KILL", pid], stderr_to_stdout: true)
          end

        _ ->
          :ok
      end

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "separate binary streams retain bounded hashes and actual nonzero status", ctx do
    result = run(ctx, "binary", chunk_size: 2)
    assert result.outcome == :complete
    assert result.exit_status == 7
    assert result.eof == %{stdout: true, stderr: true}
    assert result.stdout_bytes == 5
    assert result.stderr_bytes == 5
    assert result.stdout_sha256 == hash(<<0, 255, "out">>)
    assert result.stderr_sha256 == hash(<<254, 0, "err">>)
    assert result.max_chunk <= 2
    assert result.max_pending <= 2
  end

  test "stdout EOF does not truncate later stderr", ctx do
    result = run(ctx, "early_stdout", observer: self())
    assert result.outcome == :complete
    assert result.stderr_sha256 == hash("late-err")
    assert result.eof == %{stdout: true, stderr: true}
    events = events()
    assert index(events, {:eof, :stdout}) < index(events, {:eof, :stderr})
  end

  test "stderr EOF does not truncate later stdout", ctx do
    result = run(ctx, "early_stderr", observer: self())
    assert result.outcome == :complete
    assert result.stdout_sha256 == hash("late-out")
    events = events()
    assert index(events, {:eof, :stderr}) < index(events, {:eof, :stdout})
  end

  test "leader can die while inherited pipes still deliver late child data", ctx do
    caller = self()
    task = Task.async(fn -> run(ctx, "descendant", observer: caller) end)
    assert_receive {:transport_started, _, info}, 2000
    assert_stopped(info.os_pid)
    refute Task.yield(task, 0)
    File.write!(Path.join(ctx.root, "progress"), "release")
    result = Task.await(task, 2000)
    assert result.exit_status == 9
    assert result.outcome == :complete
    assert result.stdout_sha256 == hash("late-child")
    assert result.stderr_sha256 == hash("child-err")
    assert result.eof == %{stdout: true, stderr: true}
  end

  test "stalled consumer backpressures output and Stop stays responsive", ctx do
    caller = self()
    task = Task.async(fn -> run(ctx, "flood", consumer: caller, observer: caller) end)
    assert_receive {:transport_started, coordinator, info}, 2000
    assert_receive {:transport_chunk, ^coordinator, :stdout, _, _}, 1000
    assert_receive {:transport_chunk, ^coordinator, :stderr, _, _}, 1000
    Process.sleep(100)
    progress = progress(ctx)

    queues =
      Enum.map(
        [coordinator, info.process.pid | info.readers],
        &Process.info(&1, :message_queue_len)
      )

    Process.sleep(100)
    assert progress(ctx) == progress
    assert progress < 2_000_000
    assert Enum.all?(queues, fn {:message_queue_len, n} -> n <= 4 end)
    started = now()
    send(coordinator, :stop)
    result = Task.await(task, 2000)
    assert now() - started < 1500
    assert result.outcome == :cancelled
    assert result.max_pending == 2
    refute result.eof == %{stdout: true, stderr: true}
    assert_stopped(info.os_pid)

    IO.puts(
      "backpressure fixture: written=#{progress} bytes, queues=#{inspect(queues)}, retained_pending=2"
    )
  end

  test "absolute timeout stays responsive while consumer withholds ACK", ctx do
    caller = self()
    task = Task.async(fn -> run(ctx, "flood", consumer: caller, timeout: 300) end)
    assert_receive {:transport_chunk, _, _, _, _}, 250
    result = Task.await(task, 2000)
    assert result.outcome == :timeout
    assert result.max_pending <= 2
    refute result.eof == %{stdout: true, stderr: true}
  end

  test "Stop interrupts readers waiting on silent pipes", ctx do
    caller = self()
    task = Task.async(fn -> run(ctx, "quiet", observer: caller) end)
    assert_receive {:transport_started, coordinator, info}, 2000
    send(coordinator, :stop)
    result = Task.await(task, 2000)
    assert result.outcome == :cancelled
    assert_stopped(info.os_pid)
  end

  test "both EOFs alone are not process completion", ctx do
    result = run(ctx, "closed_alive", timeout: 150)
    assert result.outcome == :timeout
    assert result.eof == %{stdout: true, stderr: true}
    assert is_integer(result.exit_status)
  end

  test "output limit fails explicitly without unbounded retention", ctx do
    result = run(ctx, "flood", output_limit: 32_768)
    assert result.outcome == :output_limit
    assert result.stdout_bytes + result.stderr_bytes <= 32_768 + 2 * 4096
    assert result.max_chunk <= 4096
    assert result.max_pending <= 2
  end

  test "continuously arriving output cannot starve absolute deadline", ctx do
    started = now()
    result = run(ctx, "flood", timeout: 100, output_limit: 1_000_000_000)
    assert result.outcome == :timeout
    assert result.stdout_bytes > 0
    assert now() - started < 1500
  end

  test "sustained ACKed reads keep both reader stacks constant", ctx do
    caller = self()

    task =
      Task.async(fn ->
        run(ctx, "flood",
          consumer: caller,
          observer: caller,
          timeout: 5000,
          output_limit: 16_777_216
        )
      end)

    assert_receive {:transport_started, coordinator, info}, 2000
    {bytes, first} = drain_until(coordinator, info.readers, 2_097_152, 0)
    {_, last} = drain_until(coordinator, info.readers, 8_388_608, bytes)
    send(coordinator, :stop)
    assert %{outcome: :cancelled} = Task.await(task, 2000)
    assert Enum.all?(first ++ last, &(&1 < 128))
    assert Enum.max(last) <= Enum.max(first) + 8
    IO.puts("sustained reads: 2MiB stacks=#{inspect(first)}, 8MiB stacks=#{inspect(last)}")
  end

  test "Stop retains its cause when the process handles TERM by exiting zero", ctx do
    caller = self()
    task = Task.async(fn -> run(ctx, "term_zero", consumer: caller) end)
    assert_receive {:transport_chunk, coordinator, :stdout, _, "ready"}, 1000
    send(coordinator, :stop)
    result = Task.await(task, 2000)
    assert result.outcome == :cancelled
    assert result.exit_status == 0
  end

  defp run(ctx, mode, opts),
    do:
      BossTransportSpike.run(
        [ctx.binary, mode, Path.join(ctx.root, "pids"), Path.join(ctx.root, "progress")],
        opts
      )

  defp hash(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp now, do: System.monotonic_time(:millisecond)

  defp drain_until(_coordinator, readers, target, bytes) when bytes >= target do
    {bytes,
     Enum.map(readers, fn pid ->
       {:stack_size, size} = Process.info(pid, :stack_size)
       size
     end)}
  end

  defp drain_until(coordinator, readers, target, bytes) do
    receive do
      {:transport_chunk, ^coordinator, _, ref, chunk} ->
        send(coordinator, {:ack, ref})
        drain_until(coordinator, readers, target, bytes + byte_size(chunk))
    after
      2000 -> flunk("Sustained output stopped")
    end
  end

  defp progress(ctx),
    do: File.read!(Path.join(ctx.root, "progress")) |> String.trim() |> String.to_integer()

  defp scratch(kind) do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-transport-#{kind}-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    root
  end

  defp events(acc \\ []) do
    receive do
      {:transport_event, _, event} -> events([event | acc])
      {:transport_started, _, _} -> events(acc)
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp index(events, event),
    do: Enum.find_index(events, &(&1 == event)) || flunk("Missing #{inspect(event)}")

  defp assert_stopped(pid, attempts \\ 100)

  defp assert_stopped(pid, attempts) when attempts > 0 do
    case System.cmd("/bin/kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(10)
        assert_stopped(pid, attempts - 1)

      _ ->
        :ok
    end
  end

  defp assert_stopped(_, 0), do: flunk("Direct child survived")
end
