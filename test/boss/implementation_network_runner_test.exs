defmodule Boss.ImplementationNetworkRunnerTest do
  use ExUnit.Case, async: false
  alias Boss.Agents.NetworkPolicy
  alias Boss.Deliveries.Worker
  @moduletag skip: :os.type() != {:unix, :darwin}
  @profile %{"model" => "gpt-5.6-terra", "reasoning_effort" => "xhigh"}

  setup do
    root = Path.join(System.tmp_dir!(), "boss-network-runner-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    original = System.fetch_env!("PATH")
    executable = Path.join(root, "codex")

    File.write!(executable, """
    #!/usr/bin/env python3
    import json, pathlib, signal, sys, time
    signal.alarm(10)
    args = sys.argv[1:]
    assert args[args.index('--ask-for-approval') + 1] == 'never'
    assert '--ignore-user-config' in args and '--ephemeral' in args
    assert args[-1] == '-'
    mode = sys.stdin.read()
    configs = [args[i + 1] for i, value in enumerate(args) if value == '--config']
    network = [c for c in configs if c.startswith(('sandbox_workspace_write.', 'features.network_proxy.'))]
    if mode in ('enabled', 'wait'):
        assert args[args.index('--sandbox') + 1] == 'workspace-write'
        assert network == [
          'sandbox_workspace_write.network_access=true',
          'features.network_proxy.enabled=true',
          'features.network_proxy.domains={"127.0.0.1"="allow","builds.hex.pm"="allow","github.com"="allow","hex.pm"="allow","localhost"="allow","registry.npmjs.org"="allow","release-assets.githubusercontent.com"="allow","repo.hex.pm"="allow"}',
          'features.network_proxy.allow_local_binding=true']
    else:
        assert not network
    pathlib.Path('called').write_text(mode)
    print(json.dumps({'type': 'turn.started'}), flush=True)
    if mode == 'wait':
        while True: time.sleep(0.01)
    if mode == 'read-only':
        assert args[args.index('--sandbox') + 1] == 'read-only'
        pathlib.Path(args[args.index('--output-last-message') + 1]).write_text('{}')
    print(json.dumps({'type': 'turn.completed'}), flush=True)
    """)

    File.chmod!(executable, 0o700)
    System.put_env("PATH", root <> ":" <> original)
    on_exit(fn -> System.put_env("PATH", original) end)
    %{root: root}
  end

  test "production runner passes the pinned implementation policy while legacy and review stay unchanged",
       c do
    enabled =
      Worker.run_agent(:implement, c.root, "enabled", nil, @profile,
        network_policy: NetworkPolicy.profile(1)
      )

    assert enabled["status"] == "finished" and enabled["exit_code"] == 0
    assert enabled["cleanup"] == "group_empty"
    assert enabled["eof"] == %{"stdout" => true, "stderr" => true}

    legacy = Worker.run_agent(:implement, c.root, "legacy", nil, @profile)
    assert legacy["status"] == "finished" and legacy["exit_code"] == 0
    review = Worker.run_agent(:review, c.root, "read-only", &JSON.decode/1, @profile)
    assert review["status"] == "finished" and review["report"] == %{}
  end

  test "invalid or read-only networking is rejected before any child starts", c do
    for kind <- [:implement, :resolve] do
      policy =
        if kind == :implement,
          do: Map.put(NetworkPolicy.profile(1), "domains", ["*"]),
          else: NetworkPolicy.profile(1)

      assert_raise ArgumentError, fn ->
        Worker.run_agent(kind, c.root, "enabled", &JSON.decode/1, @profile,
          network_policy: policy
        )
      end

      refute File.exists?(Path.join(c.root, "called"))
    end
  end

  test "Stop still owns cleanup of an implementation with network access", c do
    parent = self()

    worker =
      spawn(fn ->
        receipt =
          Worker.run_agent(:implement, c.root, "wait", nil, @profile,
            network_policy: NetworkPolicy.profile(1)
          )

        send(parent, {:finished, self(), receipt})
      end)

    on_exit(fn -> if Process.alive?(worker), do: send(worker, :stop) end)
    eventually(fn -> File.exists?(Path.join(c.root, "called")) end)
    send(worker, :stop)
    assert_receive {:finished, ^worker, receipt}, 5_000
    assert receipt["status"] == "cancelled" and receipt["outcome"] == "cancelled"
    assert receipt["cleanup"] == "group_empty"
    assert receipt["eof"] == %{"stdout" => true, "stderr" => true}
  end

  test "only a known timeout with bounded UTF-8 capture revalidates the candidate", c do
    executable = Path.join(c.root, "slow-check")

    File.write!(executable, """
    #!/usr/bin/env python3
    import sys, time
    sys.stdout.buffer.write(b'\\xff' if sys.argv[1] == 'invalid' else b'observed before timeout')
    sys.stdout.flush()
    time.sleep(5)
    """)

    File.chmod!(executable, 0o700)

    for mode <- ["valid", "invalid", "changed", "legacy"] do
      key = make_ref()
      Process.put(key, 0)

      verify = fn ->
        count = Process.get(key)
        Process.put(key, count + 1)
        if mode == "changed" and count > 0, do: {:error, :candidate_changed}, else: :ok
      end

      config = %{"argv" => [executable, mode], "timeout_ms" => 150, "output_limit" => 1024}

      {receipt, output} =
        Worker.run_check(c.root, config, verify, verify_timeout: mode != "legacy")

      assert output == %{}
      assert receipt["cleanup"] == "group_empty"
      assert receipt["eof"] == %{"stdout" => true, "stderr" => true}
      assert receipt["output_complete"] == false and receipt["output_hash"] == nil

      if mode == "changed",
        do: assert(receipt["outcome"] == "candidate_changed"),
        else: assert(receipt["outcome"] == "timeout")

      if mode == "valid",
        do: assert(receipt["candidate_verified"] == true),
        else: refute(receipt["candidate_verified"])

      assert Process.delete(key) == if(mode in ["valid", "changed"], do: 2, else: 1)
    end
  end

  defp eventually(fun, attempts \\ 200)
  defp eventually(_, 0), do: flunk("Finite fixture did not start")

  defp eventually(fun, attempts) do
    unless fun.() do
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end
end
