defmodule Boss.IntakeAgentReportTest do
  use ExUnit.Case, async: false
  alias Boss.Agents.ReportFile
  alias Boss.Deliveries.Worker
  alias Boss.Projects.Intake.Planner
  @moduletag skip: :os.type() != {:unix, :darwin}
  @profile %{"model" => "gpt-5.6-sol", "reasoning_effort" => "high"}

  setup do
    root = Path.join(System.tmp_dir!(), "boss-intake-report-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    original = System.fetch_env!("PATH")
    codex = Path.join(root, "codex")

    File.write!(codex, """
    #!/usr/bin/env python3
    import json, pathlib, signal, sys, time
    signal.alarm(5)
    args = sys.argv[1:]
    assert args[args.index('--sandbox') + 1] == 'read-only'
    assert '--ignore-user-config' in args and '--ephemeral' in args
    mode = json.loads(sys.stdin.read())['mode']
    pathlib.Path('called').write_text(mode)
    print(json.dumps({'type': 'turn.started'}), flush=True)
    print(json.dumps({'type': 'item.completed', 'item': {'type': 'agent_message', 'text': 'RAW_SECRET_SENTINEL'}}), flush=True)
    output = pathlib.Path(args[args.index('--output-last-message') + 1])
    if mode == 'slow': time.sleep(0.45)
    if mode == 'very_slow': time.sleep(2)
    if mode == 'replaced': output.unlink()
    if mode == 'oversized': output.write_text('x' * 32769)
    elif mode != 'empty': output.write_text('{"tasks":[]}')
    print(json.dumps({'type': 'turn.completed', 'usage': {'input_tokens': 7, 'output_tokens': 3}}), flush=True)
    """)

    File.chmod!(codex, 0o700)
    System.put_env("PATH", root <> ":" <> original)
    on_exit(fn -> System.put_env("PATH", original) end)
    assert System.find_executable("codex") == codex
    %{root: root}
  end

  test "intake report receipts preserve size and fixed failure codes without raw text", c do
    for {mode, code, bytes} <- [
          {"oversized", "report_too_large", 32769},
          {"empty", "report_empty", 0},
          {"replaced", "report_replaced", 0}
        ] do
      receipt = run(c.root, mode, report_diagnostics: true)
      assert receipt["status"] == "failed"
      assert receipt["cleanup"] == "group_empty"
      assert receipt["eof"] == %{"stdout" => true, "stderr" => true}
      assert receipt["outcome"] == "invalid_report"
      assert receipt["validation_code"] == code
      assert receipt["report_bytes"] == bytes
      refute Map.has_key?(receipt, "report")
      refute inspect(receipt) =~ "RAW_SECRET_SENTINEL"
    end

    receipt = run(c.root, "valid", report_diagnostics: true)
    assert receipt["status"] == "finished"
    assert receipt["report"] == %{"tasks" => []}
    assert receipt["report_bytes"] == 12
    assert receipt["validation_code"] == "valid"
  end

  test "default agent receipts and review reader retain the 32KiB contract", c do
    receipt = run(c.root, "valid", [])
    assert receipt["status"] == "finished"
    refute Map.has_key?(receipt, "report_bytes")
    refute Map.has_key?(receipt, "validation_code")
    receipt = run(c.root, "oversized", [])
    assert receipt["outcome"] == "invalid_report"
    refute Map.has_key?(receipt, "validation_code")

    ReportFile.with_file(fn path, file ->
      File.write!(path, String.duplicate("x", 32_768))
      assert {:ok, text} = ReportFile.read(path, file)
      assert byte_size(text) == 32_768
      File.write!(path, String.duplicate("x", 32_769))
      assert {:error, :invalid_review} = ReportFile.read(path, file)
    end)
  end

  test "one absolute deadline is shared across calls and expiry launches no new process", c do
    deadline = System.monotonic_time(:millisecond) + 7000
    opts = [report_diagnostics: true, deadline_ms: deadline]
    first = run(c.root, "slow", opts)
    assert first["status"] == "finished"
    second = run(c.root, "very_slow", opts)
    assert second["outcome"] == "timeout"
    assert second["cleanup"] == "group_empty"
    assert System.monotonic_time(:millisecond) < deadline
    File.rm!(Path.join(c.root, "called"))

    assert catch_throw(run(c.root, "valid", deadline_ms: System.monotonic_time(:millisecond))) ==
             {:halt, :planning_deadline}

    refute File.exists?(Path.join(c.root, "called"))
  end

  test "Stop still prevents the next agent before its invocation", c do
    send(self(), :stop)
    assert catch_throw(run(c.root, "valid", report_diagnostics: true)) == {:halt, :cancelled}
    refute File.exists?(Path.join(c.root, "called"))
  end

  test "prelaunch Git Stop and deadline keep known ownership across the workspace boundary", c do
    for mode <- [:stop, :deadline] do
      deadline = System.monotonic_time(:millisecond) + if(mode == :stop, do: 60_000, else: 0)

      runner = fn _executable, args, opts ->
        if mode == :stop, do: send(self(), :stop)
        Planner.run_git("/nonexistent/intake-fixture-git", args, opts, deadline)
      end

      assert {:error, :cancelled} =
               Boss.Agents.Workspace.git(c.root, ["status"], runner: runner)
    end

    assert {:error, :cleanup_unknown} =
             Boss.Agents.Workspace.git(c.root, ["status"],
               runner: fn _, _, _ -> %{outcome: :failed, cleanup: :unknown} end
             )
  end

  test "final validation interrupts a Git metadata lock at the original deadline", c do
    source = Path.join(c.root, "source")
    File.mkdir!(source)

    for args <- [
          ["init", "-q", "-b", "main"],
          [
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-q",
            "--allow-empty",
            "-m",
            "base"
          ],
          ["checkout", "-q", "-b", "observer"]
        ] do
      assert {_, 0} = System.cmd("git", args, cd: source, stderr_to_stdout: true)
    end

    {source, 0} = System.cmd("/bin/pwd", ["-P"], cd: source)
    source = String.trim(source)

    project = %{
      id: 9123,
      root_path: source,
      git_common_dir: Path.join(source, ".git"),
      base_branch: "main"
    }

    assert {:ok, workspace} = Boss.Agents.Workspace.plan(project, Ecto.UUID.generate())
    intent = Map.new(workspace, fn {key, value} -> {Atom.to_string(key), value} end)
    owner = self()

    {holder, monitor} =
      spawn_monitor(fn ->
        owner_monitor = Process.monitor(owner)
        lock = {{Boss.Agents.Workspace, :worktree, project.git_common_dir}, self()}
        true = :global.set_lock(lock, [node()], 0)
        send(owner, {:lock_held, self()})

        receive do
          :release -> :ok
          {:DOWN, ^owner_monitor, :process, ^owner, _} -> :ok
        end

        :global.del_lock(lock, [node()])
      end)

    assert_receive {:lock_held, ^holder}, 1000
    started = System.monotonic_time(:millisecond)

    try do
      assert {:error, :planning_deadline} =
               Planner.validate_current(project, %{workspace: intent, deadline_ms: started + 6500})

      assert System.monotonic_time(:millisecond) - started < 3500
    after
      send(holder, :release)
      assert_receive {:DOWN, ^monitor, :process, ^holder, :normal}, 1000
    end
  end

  defp run(path, mode, opts),
    do:
      Worker.run_agent(
        :intake,
        path,
        JSON.encode!(%{mode: mode}),
        &Planner.decode_detailed(&1, []),
        @profile,
        opts
      )
end
