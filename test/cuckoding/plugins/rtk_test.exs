defmodule Cuckoding.Plugins.RTKTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Adapters.{ClaudeCode, Codex, CursorAgent, Types}
  alias Cuckoding.Plugins.RTK

  defmodule Runner do
    def start(environment, command, options), do: {:ok, {environment, command, options}}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "cuckoding-rtk-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "agent"))
    File.mkdir_p!(Path.join(root, "worktree"))
    File.mkdir_p!(Path.join(root, "artifacts"))
    binary = Path.join(root, "rtk")

    File.write!(
      binary,
      "#!/bin/sh\ncase \"$1\" in --version) echo 'rtk 0.49.0';; pipe) /bin/cat;; *) exit 7;; esac\n"
    )

    File.chmod!(binary, 0o700)
    detection = RTK.discover(directories: [root])

    policy = %{
      "enabled" => true,
      "binary" => detection.binaries["rtk"],
      "permissions" => %{"host_process" => true}
    }

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, binary: binary, policy: policy}
  end

  test "discovery uses approved locations independently of PATH and checks executable and exact version",
       %{root: root, binary: binary} do
    assert RTK.discover(directories: [root]).health == "available"
    File.chmod!(binary, 0o600)
    assert RTK.discover(directories: [root]).health == "missing"
    File.chmod!(binary, 0o700)
    File.write!(binary, "#!/bin/sh\necho 'rtk 0.50.0'\n")
    assert RTK.discover(directories: [root]).health == "version_mismatch"

    malformed =
      RTK.discover(
        directories: [root],
        command_runner: fn _, _, _ -> {"secret-canary-version", 0} end
      )

    assert malformed.health == "unhealthy"
    refute inspect(malformed) =~ "secret-canary-version"
    File.rm!(binary)
    assert RTK.discover(directories: [root]).health == "missing"
  end

  test "unavailable, disabled and changed binaries have visible fallback", %{
    policy: policy,
    binary: binary
  } do
    assert {"Instructions only", _} = RTK.status(policy, "codex")
    assert {"Disabled", _} = RTK.status(%{})
    assert {"Disabled", _} = RTK.status(Map.put(policy, "config", %{"mode" => "passthrough"}))
    assert {"Unavailable", _} = RTK.status(Map.put(policy, "binary", nil))
    File.write!(binary, "#!/bin/sh\nexit 0\n")
    assert {"Unavailable", _} = RTK.status(policy)
  end

  test "all pinned adapters keep native permissions and isolation across start and resume",
       fixture do
    for adapter <- [ClaudeCode, Codex, CursorAgent],
        role <- ~w(speculator implementor reviewer planning custom) do
      root = Path.join(fixture.root, "#{inspect(adapter)}-#{role}")
      File.mkdir_p!(Path.join(root, "agent"))
      File.mkdir_p!(Path.join(root, "worktree"))
      request = request(root, fixture.policy, role)

      options = [
        path: fixture.binary,
        api_key_helper: fixture.binary,
        run_scoped_authenticated?: true,
        runner: Runner,
        environment: %{id: "environment"},
        request: request
      ]

      assert {:ok, session} = adapter.start(request, options)
      assert session.process.launch.command.executable == fixture.binary
      refute hd(session.process.launch.command.args) == "rtk"
      assert inspect(session.process.launch) =~ "RTK: Instructions only"

      assert {:ok, resumed} =
               adapter.resume(
                 %{session | external_session_id: "12345678-1234-1234-1234-123456789abc"},
                 %{},
                 options
               )

      assert inspect(resumed.process.launch) =~ RTK.wrapper(root)
      assert {:ok, capability} = adapter.capabilities([])
      assert capability.shell_rewrite["mode"] == "instructions_only"
      args = session.process.launch.command.args

      case adapter do
        ClaudeCode -> assert "--bare" in args
        Codex -> assert "features.hooks=false" in args
        CursorAgent -> assert "enabled" in args
      end

      refute Enum.any?(args, &String.contains?(&1, "dangerously-bypass"))
    end
  end

  test "symlinked RTK storage falls back before execution", %{root: root, policy: policy} do
    File.ln_s!(Path.join(root, "worktree"), Path.join([root, "agent", "rtk"]))
    configured = RTK.prepare_request(request(root, policy, "planning"))
    assert configured.objective =~ "RTK: Unavailable"
    assert {"Unavailable", _} = RTK.status(RTK.request_policy(configured))
    refute File.exists?(Path.join([root, "worktree", "bin", "rtk"]))
  end

  test "filtering never changes the authorized command or repeats execution, including errors", %{
    root: root,
    policy: policy,
    binary: binary
  } do
    run = %{
      id: "rtk:#{Ecto.UUID.generate()}",
      plugin_snapshot_json: %{"rtk" => %{"default" => policy}}
    }

    environment = %{run_id: run.id, run_dir: root, worktree_path: Path.join(root, "worktree")}
    path = Path.join([root, "artifacts", "redacted.log"])
    File.write!(path, "[REDACTED]\n")
    completed = %{exit_status: 0, output: "[REDACTED]\n", artifact_path: path, truncated?: false}

    command = %{
      executable: "/usr/bin/printf",
      args: ["quotes ' ; && $(never)"],
      role: "declared_command:test"
    }

    for {operation, options, result} <- [
          {:exec, [], completed},
          {:exec, [raw_output: true], completed},
          {:start, [], completed},
          {:exec, [], %{completed | exit_status: 9}},
          {:exec, [], %{completed | truncated?: true}}
        ] do
      assert {:ok, ^result} =
               RTK.filter_command(run, environment, command, operation, options, fn ->
                 send(self(), {:executed, command})
                 {:ok, result}
               end)

      assert_receive {:executed, ^command}
      refute_receive {:executed, _}
    end

    assert {:ok, ^completed} =
             RTK.filter_command(run, environment, command, :exec, [], fn ->
               File.rm!(binary)
               send(self(), {:executed, command})
               {:ok, completed}
             end)

    assert_receive {:executed, ^command}
    refute_receive {:executed, _}
  end

  test "observations distinguish raw exceptions and bypasses without inferring savings" do
    for {command, observed} <- [
          {"'/run/agent/rtk/bin/rtk' git status", "rtk_invocation_reported"},
          {"rtk proxy git status --porcelain", "raw_output_exception"},
          {"git status", "bypass_reported"},
          {"echo 'rtk git status'", "unknown"}
        ] do
      observation = RTK.annotate(%{"command" => command})["rtk"]
      assert observation["observation"] == observed
      assert observation["coverage"] == "unknown"
      assert observation["reduction"] == "unknown"
    end

    assert RTK.annotate(%{"name" => "Read"}) == %{"name" => "Read"}
  end

  defp request(root, policy, role) do
    %Types.StageRequest{
      project_id: "project",
      board_id: "board",
      task_id: "task",
      run_id: "run",
      stage_key: role,
      attempt_id: "attempt",
      objective: "Inspect README without changing files.",
      worktree_path: Path.join(root, "worktree"),
      run_dir: root,
      requested_model: nil,
      grant: %{
        "tools" => ["read", "shell"],
        "deny_tools" => ["write", "network"],
        "approval_mode" => "plan",
        "paths" => [Path.join(root, "worktree")],
        "network" => "deny",
        "resource_limits" => %{"wall_ms" => 30_000}
      },
      plugins: [%{"kind" => "shell_filter", "key" => "rtk", "policy" => policy}],
      correlation_id: "correlation",
      idempotency_key: "key"
    }
  end
end
