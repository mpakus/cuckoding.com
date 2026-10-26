defmodule Boss.Agents.ProcessTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias Boss.Agents.Process, as: Command

  if :os.type() != {:unix, :darwin}, do: @moduletag(skip: "native process owner is macOS-only")

  setup_all do
    root = scratch("build")
    on_exit(fn -> File.rm_rf!(root) end)
    fixture = Path.join(root, "fixture")
    source = Path.expand("../../support/fixtures/process_fixture.c", __DIR__)

    assert {"", 0} =
             System.cmd("cc", ["-Wall", "-Wextra", "-Werror", "-O2", source, "-o", fixture],
               stderr_to_stdout: true
             )

    fork_delay = Path.join(root, "fork_delay.dylib")
    delay_source = Path.expand("../../support/fixtures/fork_delay.c", __DIR__)

    assert {"", 0} =
             System.cmd(
               "cc",
               ["-Wall", "-Wextra", "-Werror", "-dynamiclib", delay_source, "-o", fork_delay],
               stderr_to_stdout: true
             )

    %{fixture: fixture, fork_delay: fork_delay}
  end

  setup do
    root = scratch("run")

    on_exit(fn ->
      for {_role, pid} <- pids(root) do
        {command, _} =
          System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "command="], stderr_to_stdout: true)

        if String.contains?(command, root),
          do: System.cmd("/bin/kill", ["-KILL", to_string(pid)], stderr_to_stdout: true)
      end

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "separate binary bytes, genuine EOF and nonzero exit survive transport", ctx do
    {result, output} = capture(ctx, "binary")
    assert result.outcome == :exited, inspect(result)
    assert result.exit_kind == :exit
    assert result.exit_code == 7
    assert result.signal == nil
    assert result.cleanup == :group_empty
    assert result.eof == %{stdout: true, stderr: true}
    assert output == %{stdout: <<0, 255, "out">>, stderr: <<254, 0, "err">>}
  end

  test "explicit exit137 is distinct from actual SIGKILL", ctx do
    assert %{
             outcome: :exited,
             exit_kind: :exit,
             exit_code: 137,
             signal: nil,
             cleanup: :group_empty
           } = run(ctx, "exit137")

    assert %{
             outcome: :exited,
             exit_kind: :signal,
             exit_code: nil,
             signal: 9,
             cleanup: :group_empty
           } = run(ctx, "signal")
  end

  test "the parent establishes group ownership before a fast command may execute", ctx do
    {result, output} = capture(ctx, "binary", env: [{"DYLD_INSERT_LIBRARIES", ctx.fork_delay}])
    assert result.outcome == :exited, inspect(result)
    assert result.exit_kind == :exit
    assert result.exit_code == 7
    assert result.cleanup == :group_empty
    assert result.eof == %{stdout: true, stderr: true}
    assert output == %{stdout: <<0, 255, "out">>, stderr: <<254, 0, "err">>}
  end

  test "large stdin is delivered exactly once and all callbacks finish before return", ctx do
    input = :binary.copy(<<0, 255, 47>>, 65_536)
    {result, output} = capture(ctx, "echo", input: input)
    assert %{outcome: :exited, exit_code: 0, cleanup: :group_empty} = result
    assert output.stdout == input
    assert output.stderr == ""
  end

  test "slow acknowledged consumption after leader exit does not trigger drain cleanup", ctx do
    result =
      run(ctx, "binary",
        on_event: fn
          {:stdout, _} ->
            Process.sleep(700)
            :ok

          _ ->
            :ok
        end
      )

    assert %{
             outcome: :exited,
             exit_code: 7,
             cleanup: :group_empty,
             eof: %{stdout: true, stderr: true}
           } = result
  end

  test "each early stream EOF preserves the other stream's late bytes", ctx do
    for {mode, expected} <- [
          {"early_stdout", %{stdout: "", stderr: "late"}},
          {"early_stderr", %{stdout: "late", stderr: ""}}
        ] do
      {result, output} = capture(ctx, mode)
      assert result.outcome == :exited
      assert result.eof == %{stdout: true, stderr: true}
      assert result.cleanup == :group_empty
      assert output == expected
    end
  end

  test "natural drain grace preserves short inherited tails after leader exit", ctx do
    {result, output} = capture(ctx, "descendant")
    assert %{outcome: :exited, exit_code: 9, cleanup: :group_empty} = result
    assert output == %{stdout: "late-child", stderr: "child-err"}
    assert_dead(pids(ctx.root)["child"])
  end

  test "a stubborn child after leader exit is killed and never reported ordinary success", ctx do
    result = run(ctx, "orphan")

    assert %{outcome: :failed, reason: :lingering_processes, exit_code: 0, cleanup: :group_empty} =
             result

    assert_dead(pids(ctx.root)["child"])
  end

  test "Stop escalates for the entire stubborn process group", ctx do
    task = Task.async(fn -> run(ctx, "tree") end)
    eventually(fn -> Map.has_key?(pids(ctx.root), "ready") end)
    send(task.pid, :stop)

    assert %{outcome: :cancelled, cleanup: :group_empty, exit_kind: :signal, signal: 9} =
             Task.await(task, 4000)

    assert_dead(pids(ctx.root)["leader"])
    assert_dead(pids(ctx.root)["child"])
  end

  test "Stop cause survives a CLI handling TERM with exit0", ctx do
    task = Task.async(fn -> run(ctx, "term_zero") end)
    eventually(fn -> Map.has_key?(pids(ctx.root), "ready") end)
    send(task.pid, :stop)

    assert %{outcome: :cancelled, exit_kind: :exit, exit_code: 0, cleanup: :group_empty} =
             Task.await(task, 4000)
  end

  test "immediate Stop is safe across the fork and process-group setup window", ctx do
    Enum.each(1..12, fn _ ->
      task = Task.async(fn -> run(ctx, "quiet") end)
      send(task.pid, :stop)

      assert %{outcome: :cancelled, cleanup: :group_empty, exit_kind: kind} =
               Task.await(task, 4000)

      assert kind in [:exit, :signal]
    end)
  end

  test "immediate Stop is retained while a maximum stdin packet is queued", ctx do
    input = :binary.copy("x", 1_048_576)

    Enum.each(1..4, fn _ ->
      task =
        Task.async(fn ->
          send(self(), :stop)
          run(ctx, "quiet", input: input)
        end)

      assert %{outcome: :cancelled, cleanup: :group_empty} = Task.await(task, 4000)
    end)
  end

  test "Stop stays responsive while the output callback is stalled", ctx do
    parent = self()

    callback = fn
      {:started, _} ->
        :ok

      {_, _} ->
        send(parent, :stalled)

        receive do
          :never -> :ok
        end
    end

    task = Task.async(fn -> run(ctx, "flood", on_event: callback) end)
    assert_receive :stalled, 2000
    {:monitors, [{:process, owner}]} = Process.info(task.pid, :monitors)
    {:links, links} = Process.info(owner, :links)
    workers = [owner | Enum.filter(links, &is_pid/1)]
    Process.sleep(100)
    queues = Enum.map(workers, &Process.info(&1, :message_queue_len))
    assert Enum.all?(queues, fn {:message_queue_len, n} -> n <= 2 end)
    started = System.monotonic_time(:millisecond)
    send(task.pid, :stop)
    assert %{outcome: :cancelled, cleanup: :group_empty} = result = Task.await(task, 4000)
    assert result.stdout_bytes + result.stderr_bytes <= 8192
    assert System.monotonic_time(:millisecond) - started < 2500
    assert_dead(pids(ctx.root)["leader"])
  end

  test "quiet runtime and output limits produce explicit failures", ctx do
    assert %{outcome: :timeout, cleanup: :group_empty} = run(ctx, "quiet", timeout_ms: 100)

    assert %{outcome: :output_limit, cleanup: :group_empty} =
             run(ctx, "flood", output_limit: 8192)
  end

  test "EOF alone does not complete a still living process", ctx do
    assert %{outcome: :timeout, eof: %{stdout: true, stderr: true}, cleanup: :group_empty} =
             run(ctx, "closed_alive", timeout_ms: 100)
  end

  test "runtime deadline also stops a stalled callback", ctx do
    parent = self()

    task =
      Task.async(fn ->
        run(ctx, "flood",
          timeout_ms: 300,
          on_event: fn
            {:started, _} ->
              :ok

            _ ->
              send(parent, :stalled)

              receive do
                :never -> :ok
              end
          end
        )
      end)

    assert_receive :stalled, 2000
    assert %{outcome: :timeout, cleanup: :group_empty} = Task.await(task, 4000)
    assert_dead(pids(ctx.root)["leader"])
  end

  test "caller death cleans its group while the rest of BEAM remains alive", ctx do
    caller = spawn(fn -> run(ctx, "tree") end)
    eventually(fn -> Map.has_key?(pids(ctx.root), "ready") end)
    owned = pids(ctx.root)
    Process.exit(caller, :kill)
    assert_dead(owned["leader"])
    assert_dead(owned["child"])
    assert_dead(owned["guardian"])
  end

  test "caller loss immediately after coordinator creation does not strand a process", ctx do
    Enum.each(1..8, fn _ ->
      caller = spawn(fn -> run(ctx, "quiet") end)
      owner = coordinator(caller)
      monitor = Process.monitor(owner)
      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^owner, _}, 4000
      if pid = pids(ctx.root)["leader"], do: assert_dead(pid)
      if pid = pids(ctx.root)["guardian"], do: assert_dead(pid)
    end)
  end

  test "repeated calls preserve caller flags and do not leave protocol messages", ctx do
    flags = Process.info(self(), :trap_exit)

    Enum.each(1..20, fn _ ->
      assert %{outcome: :exited, exit_code: 137, cleanup: :group_empty} = run(ctx, "exit137")
    end)

    assert Process.info(self(), :trap_exit) == flags
    assert Process.info(self(), :message_queue_len) == {:message_queue_len, 0}
  end

  test "helper SIGKILL yields unknown cleanup without signaling a cached PID", ctx do
    task = Task.async(fn -> run(ctx, "tree") end)
    eventually(fn -> Map.has_key?(pids(ctx.root), "ready") end)
    owned = pids(ctx.root)

    assert {_, 0} =
             System.cmd("/bin/kill", ["-KILL", to_string(owned["guardian"])],
               stderr_to_stdout: true
             )

    assert %{outcome: :failed, cleanup: :unknown, reason: :helper_lost} = Task.await(task, 3000)
    assert alive?(owned["leader"])
    # Only this bounded fixture's recorded, still-matching processes are cleaned by on_exit.
  end

  test "whole BEAM death closes the private control channel and cleans its group", ctx do
    code =
      "Boss.Agents.Process.run(#{inspect(ctx.fixture)}, [\"tree\", #{inspect(Path.join(ctx.root, "pids"))}], cd: #{inspect(ctx.root)}, timeout_ms: 10000)"

    vm =
      Port.open({:spawn_executable, System.find_executable("elixir")}, [
        :binary,
        :exit_status,
        args: ["-pa", Application.app_dir(:boss, "ebin"), "-e", code]
      ])

    {:os_pid, vm_pid} = Port.info(vm, :os_pid)

    on_exit(fn ->
      try do
        Port.close(vm)
      rescue
        ArgumentError -> :ok
      end
    end)

    eventually(fn -> Map.has_key?(pids(ctx.root), "ready") end, 400)
    owned = pids(ctx.root)
    assert {_, 0} = System.cmd("/bin/kill", ["-KILL", to_string(vm_pid)], stderr_to_stdout: true)
    assert_dead(owned["leader"])
    assert_dead(owned["child"])
    assert_dead(owned["guardian"])
    assert_receive {^vm, {:exit_status, _}}, 3000
  end

  test "callback failure never logs prompt or output contents", ctx do
    secret = "BOSS_PRIVATE_SENTINEL_#{System.unique_integer([:positive])}"

    log =
      capture_log(fn ->
        assert %{outcome: :failed, reason: :consumer_failed, cleanup: :group_empty} =
                 run(ctx, "echo",
                   input: secret,
                   on_event: fn
                     {:stdout, _} -> raise secret
                     _ -> :ok
                   end
                 )
      end)

    refute log =~ secret
  end

  defp run(ctx, mode, opts \\ []),
    do:
      Command.run(
        ctx.fixture,
        [mode, Path.join(ctx.root, "pids")],
        Keyword.merge([cd: ctx.root, timeout_ms: 5000], opts)
      )

  defp capture(ctx, mode, opts \\ []) do
    table = :ets.new(:output, [:public, :set])
    :ets.insert(table, [{:stdout, ""}, {:stderr, ""}])

    callback = fn
      {:started, _} ->
        :ok

      {stream, bytes} ->
        [{^stream, previous}] = :ets.lookup(table, stream)
        :ets.insert(table, {stream, previous <> bytes})
        :ok
    end

    try do
      result = run(ctx, mode, Keyword.put(opts, :on_event, callback))
      {result, Map.new(:ets.tab2list(table))}
    after
      :ets.delete(table)
    end
  end

  defp scratch(kind) do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-process-#{kind}-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    root
  end

  defp pids(root) do
    case File.read(Path.join(root, "pids")) do
      {:ok, text} ->
        text
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case String.split(line, ":") do
            [role, value] ->
              case Integer.parse(value) do
                {pid, ""} -> [{role, pid}]
                _ -> []
              end

            _ ->
              []
          end
        end)
        |> Map.new()

      _ ->
        %{}
    end
  end

  defp alive?(pid) do
    case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "stat="], stderr_to_stdout: true) do
      {status, 0} -> not String.contains?(status, "Z")
      _ -> false
    end
  end

  defp assert_dead(pid), do: eventually(fn -> not alive?(pid) end, 300)

  defp coordinator(caller, remaining \\ 100)

  defp coordinator(caller, remaining) when remaining > 0 do
    case Process.info(caller, :monitors) do
      {:monitors, [{:process, owner}]} ->
        owner

      _ ->
        Process.sleep(1)
        coordinator(caller, remaining - 1)
    end
  end

  defp coordinator(_, 0), do: flunk("coordinator did not start")
  defp eventually(fun, remaining \\ 200)

  defp eventually(fun, remaining) when remaining > 0 do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          eventually(fun, remaining - 1)
        )
  end

  defp eventually(_, 0), do: flunk("condition did not become true")
end
