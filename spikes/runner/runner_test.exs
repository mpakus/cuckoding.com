Code.require_file("runner.exs", __DIR__)
ExUnit.start(assert_receive_timeout: 3_000)

defmodule BossRunnerSpikeTest do
  use ExUnit.Case, async: false

  defp run(mode, opts \\ []), do: BossRunnerSpike.run(command(mode), opts)

  defp command(mode, extra \\ []),
    do: [System.find_executable("python3"), Path.join(__DIR__, "fixture.py"), mode] ++ extra

  test "standard Port captures stderr by merging it into the JSONL stream" do
    [executable | args] = command("chunked")

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
      ])

    assert port_output(port, "") ==
             "{\"type\":\"thread.started\"}\n{\"type\":\"turn.completed\"}\ndiagnostic\n"
  end

  test "chunked JSONL keeps streams separate and requires terminal plus clean exit" do
    result = run("chunked")
    assert result.outcome == :completed
    assert result.exit == {:status, 0}
    assert result.event_types == %{"thread.started" => 1, "turn.completed" => 1}
    assert result.stderr == "diagnostic\n"
    assert result.stdout_bytes == 52
  end

  test "invalid, nonobject and unterminated JSONL cannot pass" do
    for {mode, reason} <- [
          {"invalid", :invalid_json},
          {"nonobject", :invalid_event},
          {"unterminated", :unterminated_jsonl}
        ] do
      assert run(mode).outcome == reason
    end
  end

  test "oversized line is rejected with a bounded retained buffer" do
    result = run("oversized", line_limit: 256)
    assert result.outcome == :line_limit
    assert result.max_buffer <= 256
  end

  test "stderr flood and excessive events have explicit limits" do
    result = run("flood", output_limit: 32_768)
    assert result.outcome == :output_limit
    assert byte_size(result.stderr) <= 1024
    assert run("events", event_limit: 20).outcome == :event_limit
  end

  test "nonzero exit overrides a completion event" do
    result = run("failed")
    assert result.outcome == :process_failed
    assert result.exit == {:status, 7}
  end

  test "failed or missing terminal events cannot become success at exit zero" do
    assert run("protocol_failed").outcome == :protocol_failed
    assert run("missing_terminal").outcome == :missing_terminal
  end

  test "signal termination is distinguished from an ordinary status" do
    result = run("signal")
    assert result.outcome == :process_failed
    assert match?({:signal, _, _}, result.exit)
  end

  test "idle timeout and absolute timeout are separate and survive normalized exit zero" do
    idle = run("stall", idle_timeout: 100)
    assert idle.outcome == :idle_timeout
    assert idle.exit == {:status, 0}
    assert run("busy", timeout: 150, idle_timeout: 100).outcome == :timeout
  end

  test "explicit cancellation kills a stubborn leader and its ordinary descendant" do
    pidfile = temp_path("tree")
    task = Task.async(fn -> BossRunnerSpike.run(command("tree", [pidfile])) end)
    pids = await_pids(pidfile)
    on_exit(fn -> cleanup(pids, pidfile) end)
    send(task.pid, :cancel)
    assert Task.await(task, 4_000).outcome == :cancelled
    assert eventually(fn -> dead?(pids["leader"]) and dead?(pids["child"]) end)
  end

  test "owner crash produces DOWN and linked native cleanup, never a success result" do
    pidfile = temp_path("owner")
    test_pid = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        result = BossRunnerSpike.run(command("tree", [pidfile]))
        send(test_pid, {:unexpected_result, result})
      end)

    pids = await_pids(pidfile)
    on_exit(fn -> cleanup(pids, pidfile) end)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}
    assert eventually(fn -> dead?(pids["leader"]) and dead?(pids["child"]) end)
    refute_received {:unexpected_result, _}
  end

  test "known boundary: a detached descendant escapes process-group cancellation" do
    pidfile = temp_path("detached")
    task = Task.async(fn -> BossRunnerSpike.run(command("detached", [pidfile])) end)
    pids = await_pids(pidfile)
    on_exit(fn -> cleanup(pids, pidfile) end)
    send(task.pid, :cancel)
    assert Task.await(task, 4_000).outcome == :cancelled
    refute dead?(pids["child"])
  end

  test "known boundary: leader completion does not prove a stubborn child exited" do
    pidfile = temp_path("orphan")
    result = BossRunnerSpike.run(command("orphan", [pidfile]))
    pids = await_pids(pidfile)
    on_exit(fn -> cleanup(pids, pidfile) end)
    assert result.outcome == :completed
    refute dead?(pids["child"])
  end

  test "whole BEAM crash keeps started intent unresolved and native helper cleans its group" do
    pidfile = temp_path("backend-tree")
    intent = temp_path("intent")
    elixir = Path.expand("../../bin/elixir", to_string(:code.lib_dir(:elixir)))

    script = """
    File.write!(#{inspect(intent)}, JSON.encode!(%{state: "started", beam: System.pid()}))
    BossRunnerSpike.run(#{inspect(command("tree", [pidfile]))})
    File.write!(#{inspect(intent)}, JSON.encode!(%{state: "completed"}))
    """

    port =
      Port.open({:spawn_executable, elixir}, [
        :binary,
        :exit_status,
        args: ["-r", Path.join(__DIR__, "runner.exs"), "-e", script]
      ])

    pids = await_pids(pidfile)

    on_exit(fn ->
      cleanup(pids, pidfile)
      File.rm(intent)
    end)

    started = intent |> File.read!() |> JSON.decode!()
    assert {_, 0} = System.cmd("/bin/kill", ["-KILL", started["beam"]])
    assert_receive {^port, {:exit_status, status}}
    assert status != 0
    assert eventually(fn -> dead?(pids["leader"]) and dead?(pids["child"]) end, 300)
    assert intent |> File.read!() |> JSON.decode!() == started
  end

  defp temp_path(name) do
    root =
      Path.join(System.tmp_dir!(), "boss-runner-#{Base.encode16(:crypto.strong_rand_bytes(12))}")

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Path.join(root, "#{name}.json")
  end

  defp port_output(port, data) do
    receive do
      {^port, {:data, chunk}} -> port_output(port, data <> chunk)
      {^port, {:exit_status, 0}} -> data
    after
      3_000 -> flunk("Port fixture did not exit")
    end
  end

  defp await_pids(path) do
    assert eventually(fn ->
             case File.read(path) do
               {:ok, data} -> match?({:ok, %{"leader" => _, "child" => _}}, JSON.decode(data))
               _ -> false
             end
           end)

    path |> File.read!() |> JSON.decode!()
  end

  defp dead?(pid) do
    case System.cmd("ps", ["-o", "stat=", "-p", Integer.to_string(pid)]) do
      {_, status} when status != 0 -> true
      {state, 0} -> String.starts_with?(String.trim(state), "Z")
    end
  end

  defp cleanup(pids, path) do
    for pid <- Map.values(pids),
        not dead?(pid),
        do: System.cmd("/bin/kill", ["-KILL", Integer.to_string(pid)])

    File.rm(path)
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(_fun, 0), do: false

  defp eventually(fun, attempts) do
    if fun.(),
      do: true,
      else:
        (
          Process.sleep(30)
          eventually(fun, attempts - 1)
        )
  end
end
