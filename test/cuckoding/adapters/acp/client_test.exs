defmodule Cuckoding.Adapters.ACP.ClientTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.ActivityStream
  alias Cuckoding.Adapters.ACP.Client
  alias Cuckoding.Adapters.Types
  alias Cuckoding.Execution
  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.LocalHostInspector
  alias Cuckoding.Execution.LocalProcessRunner
  alias Cuckoding.Execution.ProcessRecord
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Projects
  alias Cuckoding.RunControl
  alias Cuckoding.Telemetry.UsageRecord
  alias Cuckoding.Workflows

  setup do
    root = Path.join(System.tmp_dir!(), "cuckoding-acp-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "worktree"))
    File.mkdir_p!(Path.join(root, "run"))
    on_exit(fn -> File.rm_rf!(root) end)
    f = fixture(root)
    on_exit(fn -> LocalProcessRunner.destroy(f.environment, grace_ms: 25) end)
    f
  end

  test "negotiates, saves identity before work, streams durable public events and returns typed output",
       f do
    :ok = ActivityStream.subscribe(f.request.run_id)
    task = execute(f, "success")
    assert_receive {:client_ready, session}, 3_000
    assert session.state == "starting"

    event = wait_event(f.request.run_id, "tool.started")
    assert event.payload["agent_session_id"] == f.stored.id
    assert Repo.get!(AgentSession, f.stored.id).external_session_id == "fixture-session"
    assert Repo.get!(AgentSession, f.stored.id).actual_model == "fixture-model"
    assert_receive {:activity_event, _, _}
    assert {:ok, result} = Task.await(task, 5_000)
    assert result.transport == :acp
    assert result.structured_output == %{"summary" => "done"}
    assert LocalHostInspector.groups_empty?([result.process.pgid])
    assert Repo.get!(ProcessRecord, result.process.id).agent_session_id == f.stored.id

    events = Repo.all(from e in RunEvent, where: e.run_id == ^f.request.run_id)
    text = inspect(events) <> File.read!(result.artifact_path)

    for forbidden <- ~w(fixture-secret-canary private-reasoning-canary private-tool-canary),
        do: refute(text =~ forbidden)

    assert text =~ "[REDACTED]"
    refute File.read!(result.artifact_path) =~ "jsonrpc"

    assert [usage] = Repo.all(from u in UsageRecord, where: u.agent_session_id == ^f.stored.id)
    assert usage.input_tokens == 5
    assert usage.output_tokens == 3
    assert usage.cache_read_tokens == 2
    assert usage.cache_write_tokens == nil
    assert usage.cost_micros == nil
    assert usage.source == "provider_reported"

    messages = requests(f)

    assert Enum.map(messages, & &1["method"]) ==
             ~w(initialize session/new session/set_mode session/set_model session/prompt)

    assert hd(messages)["params"]["clientCapabilities"]["terminal"] == false
    assert Enum.at(messages, 1)["params"]["mcpServers"] == []
  end

  test "loads only negotiated sessions and does not re-account replayed history", f do
    assert {:ok, _result} =
             execute(f, "success", resume_session: "saved-session") |> Task.await(5_000)

    assert Repo.get!(AgentSession, f.stored.id).external_session_id == "saved-session"
    assert Enum.at(requests(f), 1)["method"] == "session/load"
    refute inspect(ActivityStream.list(f.request.run_id, 0)) =~ "historical-message"
    assert Repo.aggregate(UsageRecord, :count) == 1
  end

  for reason <- ~w(max_tokens max_turn_requests) do
    test "preserves the typed #{reason} stop after owned cleanup", f do
      assert {:error, {:acp_turn_stopped, unquote(reason)}} =
               execute(f, unquote(reason)) |> Task.await(5_000)

      assert_owned_cleanup(f)

      assert Cuckoding.OrchestrationFailure.recovery_class({:acp_turn_stopped, unquote(reason)}) ==
               "continuation"
    end
  end

  for adapter <- ~w(codex claude_code),
      {scenario, expected} <- [
        {"provider-rate", :provider_rate_limited},
        {"provider-overloaded", :provider_unavailable},
        {"provider-quota", :provider_failure_requires_attention}
      ] do
    test "normalizes #{adapter} #{scenario} metadata without retaining private error details",
         f do
      stored = Repo.update!(Ecto.Changeset.change(f.stored, adapter_key: unquote(adapter)))
      f = %{f | stored: stored}

      assert {:error, unquote(expected)} =
               execute(f, unquote(scenario), adapter: unquote(adapter)) |> Task.await(5_000)

      assert_owned_cleanup(f)
      events = inspect(ActivityStream.list(f.request.run_id, 0))
      refute events =~ "private-reasoning-canary"
      refute events =~ "fixture-secret-canary"
      capabilities = hd(requests(f))["params"]["clientCapabilities"]
      assert capabilities["terminal"] == false
      assert capabilities["_meta"]["jetbrains"]["air"]["capabilities"] == ["sessionFailure"]
    end
  end

  test "compatible continuation falls back before any prompt when loading is no longer supported",
       f do
    Repo.update!(Ecto.Changeset.change(f.stored, continuation_mode: "native"))

    assert {:ok, _} =
             execute(f, "no-load", resume_session: "saved", continuation_fallback: true)
             |> Task.await(5_000)

    assert Enum.at(requests(f), 1)["method"] == "session/new"
    assert Enum.count(requests(f), &(&1["method"] == "session/prompt")) == 1
    assert Repo.get!(AgentSession, f.stored.id).continuation_mode == "saved_evidence"
    assert Repo.aggregate(UsageRecord, :count) == 1
  end

  test "model selection acknowledgement does not invent an observed model", f do
    task = execute(f, "model-unreported")
    assert_receive {:client_ready, %{requested_model: "fixture-model", actual_model: nil}}, 3_000
    assert {:ok, _} = Task.await(task)
    assert Repo.get!(AgentSession, f.stored.id).actual_model == nil
  end

  test "negotiates modern configuration and persists the explicitly reported model", f do
    task = execute(f, "modern")
    assert {:ok, _} = Task.await(task)
    assert Repo.get!(AgentSession, f.stored.id).actual_model == "fixture-model"
    assert Enum.any?(requests(f), &(&1["method"] == "session/set_config_option"))
    refute Enum.any?(requests(f), &(&1["method"] == "session/set_model"))
  end

  test "configuration notifications cannot expand the permission mode", f do
    assert {:error, :acp_configuration_changed} = execute(f, "config-drift") |> Task.await(5_000)
    assert_owned_cleanup(f)
  end

  test "Codex uses the packaged bridge and common workflow boundary", f do
    bridge =
      Cuckoding.ACPBridgeFixture.install(Path.join(f.environment.run_dir, "bridge"), "codex")

    request = %{
      f.request
      | grant: %{"approval_mode" => "plan", "resource_limits" => %{"wall_ms" => 5_000}}
    }

    assert {:ok, session} =
             Cuckoding.Adapters.Codex.start(request,
               path: "/usr/bin/true",
               bridge_directory: bridge,
               run_scoped_authenticated?: true,
               runner: LocalProcessRunner,
               environment: f.environment,
               redact: ["fixture-secret-canary"]
             )

    assert session.process.runner == Client
    assert session.effective_grant.enforced["sandbox_mode"] == "read-only"
    assert {:ok, result} = Cuckoding.Adapters.await_session(f.stored, session)
    assert result.structured_output == %{"summary" => "done"}
    assert_owned_cleanup(f)
  end

  test "Cursor launches native ACP and uses the shared workflow result boundary", f do
    path = Path.join(f.environment.run_dir, "cursor-acp-fixture")
    File.cp!(Path.expand("test/support/fixtures/acp_runtime.rb"), path)
    File.chmod!(path, 0o700)

    {:ok, stored} =
      Execution.create_agent_session(%{
        stage_attempt_id: f.request.attempt_id,
        adapter_key: "cursor_agent",
        requested_model: "fixture-model",
        effective_grant_json: %{}
      })

    request = %{
      f.request
      | grant: %{
          "approval_mode" => "plan",
          "tools" => ["read"],
          "paths" => [f.environment.worktree_path],
          "network" => "deny",
          "resource_limits" => %{"wall_ms" => 5_000}
        }
    }

    assert {:ok, session} =
             Cuckoding.Adapters.CursorAgent.start(request,
               path: path,
               run_scoped_authenticated?: true,
               runner: LocalProcessRunner,
               environment: f.environment,
               redact: ["fixture-secret-canary"]
             )

    assert session.process.runner == Client
    assert session.effective_grant.enforced["mode"] == "plan"
    assert {:ok, result} = Cuckoding.Adapters.await_session(stored, session)

    observed = Repo.get!(AgentSession, stored.id)
    assert observed.requested_model == "fixture-model"
    assert observed.actual_model == "fixture[effort=high]"

    assert Enum.any?(requests(f), fn message ->
             message["method"] == "session/set_config_option" and
               message["params"]["value"] == "fixture[effort=high]"
           end)

    assert {:ok, %{"summary" => "done"}} =
             Cuckoding.Adapters.OutputParser.extract("cursor_agent", result)

    assert :ok = ActivityStream.record_provider_messages(stored, "cursor_agent", result)
    assert Repo.aggregate(UsageRecord, :count) == 1
    assert_owned_cleanup(f)
  end

  test "Claude passes the saved configuration through ACP before delivery", f do
    bridge =
      Cuckoding.ACPBridgeFixture.install(Path.join(f.environment.run_dir, "bridge"), "claude")

    {:ok, stored} =
      Execution.create_agent_session(%{
        stage_attempt_id: f.request.attempt_id,
        adapter_key: "claude_code",
        requested_model: "fixture-model",
        effective_grant_json: %{}
      })

    request = %{
      f.request
      | grant: %{
          "approval_mode" => "plan",
          "tools" => ["Read"],
          "resource_limits" => %{"wall_ms" => 5_000}
        }
    }

    assert {:ok, session} =
             Cuckoding.Adapters.ClaudeCode.start(request,
               path: "/usr/bin/true",
               api_key_helper: "/usr/bin/true",
               run_scoped_authenticated?: true,
               bridge_directory: bridge,
               runner: LocalProcessRunner,
               environment: f.environment,
               redact: ["fixture-secret-canary"]
             )

    assert {:ok, result} = Cuckoding.Adapters.await_session(stored, session)
    assert result.structured_output == %{"summary" => "done"}
    params = Enum.find(requests(f), &(&1["method"] == "session/new"))["params"]
    assert params["cwd"] == f.request.worktree_path
    assert params["_meta"]["claudeCode"]["options"]["allowedTools"] == ["Read"]
    assert params["_meta"]["claudeCode"]["options"]["settingSources"] == []
    assert_owned_cleanup(f)
  end

  for {scenario, options, expected} <- [
        {"wrong-version", [], :acp_protocol_mismatch},
        {"no-load", [resume_session: "saved"], :acp_load_unsupported}
      ] do
    test "refuses #{scenario} negotiation before any prompt", f do
      assert {:error, unquote(expected)} =
               execute(f, unquote(scenario), unquote(options)) |> Task.await(5_000)

      refute Enum.any?(requests(f), &(&1["method"] == "session/prompt"))
    end
  end

  test "run Stop interrupts unresponsive negotiation without waiting for the provider timeout",
       f do
    task = execute(f, "wait-initialize")
    assert_receive {:client_ready, _session}, 1_000
    wait_event(f.request.run_id, "agent.process_bound")
    control = Task.async(fn -> RunControl.control(f.request.run_id, "stop") end)
    assert {:ok, %{state: "cancelled"}} = Task.await(control, 3_000)
    assert {:error, :acp_cancelled} = Task.await(task)
    assert Repo.get!(AgentSession, f.stored.id).state == "cancelled"
    assert_owned_cleanup(f)
    refute Enum.any?(requests(f), &(&1["method"] == "session/prompt"))
  end

  test "run Stop cancels the ACP turn and late observations preserve cancellation", f do
    task = execute(f, "wait")
    assert_receive {:client_ready, session}, 1_000
    wait_event(f.request.run_id, "tool.started")
    assert {:ok, %{state: "cancelled"}} = RunControl.control(f.request.run_id, "stop")
    assert {:error, :acp_cancelled} = Task.await(task)
    assert Enum.any?(requests(f), &(&1["method"] == "session/cancel"))

    assert {:ok, stored} =
             Cuckoding.Adapters.record_session_observation(f.stored, %{session | state: "done"})

    assert stored.state == "cancelled"

    refute Repo.exists?(
             from e in RunEvent,
               where: e.run_id == ^f.request.run_id and e.event_type == "session.failed"
           )

    assert_owned_cleanup(f)
  end

  test "pause before negotiation retains pending input and resume sends exactly one prompt", f do
    task = execute(f, "wait", wait_for_bind: true)
    assert_receive {:client_ready, _session}, 1_000
    assert {:ok, %{state: "paused"}} = RunControl.control(f.request.run_id, "pause")
    send(task.pid, :bind_session)
    wait_event(f.request.run_id, "agent.process_bound")
    assert Repo.get!(AgentSession, f.stored.id).state == "paused"
    assert {:ok, %{state: "running"}} = RunControl.control(f.request.run_id, "resume")
    wait_event(f.request.run_id, "tool.started")
    assert {:ok, _} = RunControl.control(f.request.run_id, "pause")
    assert {:ok, %{state: "cancelled"}} = RunControl.control(f.request.run_id, "stop")
    assert {:error, :acp_cancelled} = Task.await(task)
    assert Enum.count(requests(f), &(&1["method"] == "session/prompt")) == 1
    assert Repo.get!(AgentSession, f.stored.id).state == "cancelled"
    assert_owned_cleanup(f)
  end

  test "a ready client stays cancellable while durable admission is paused", f do
    task = execute(f, "wait", wait_for_bind: true)
    assert_receive {:client_ready, _session}, 1_000
    assert {:ok, _} = RunControl.control(f.request.run_id, "pause")
    send(task.pid, :bind_session)
    wait_event(f.request.run_id, "agent.process_bound")
    # Exercise the interval after process resume but before durable admission reopens.
    assert {:ok, _} = LocalProcessRunner.resume(f.environment)
    wait_event(f.request.run_id, "session.started")
    control = Task.async(fn -> RunControl.control(f.request.run_id, "stop") end)
    assert {:ok, %{state: "cancelled"}} = Task.await(control, 3_000)
    assert {:error, :acp_cancelled} = Task.await(task)
    refute Enum.any?(requests(f), &(&1["method"] == "session/prompt"))
    assert_owned_cleanup(f)
  end

  test "recovery requires the same live client, saved session and verified process", f do
    task = execute(f, "wait")
    assert_receive {:client_ready, session}, 1_000
    wait_event(f.request.run_id, "tool.started")
    session = %{session | external_session_id: "fixture-session"}
    inspection = %{process: :matching, session: :available}
    assert {:ok, ^session} = Cuckoding.Adapters.Codex.recover(session, inspection, [])
    refute Client.live_session?(%{session | session_id: "unrelated"}, inspection)
    assert {:ok, _} = RunControl.control(f.request.run_id, "pause")
    assert Client.live_session?(session, inspection)
    assert {:ok, _} = RunControl.control(f.request.run_id, "stop")
    assert {:error, :acp_cancelled} = Task.await(task)
    refute Client.live_session?(session, inspection)
    assert Enum.count(requests(f), &(&1["method"] == "session/prompt")) == 1
  end

  for {scenario, expected} <- [
        {"wrong-session", :acp_session_mismatch},
        {"malformed", :acp_invalid_message},
        {"partial", :acp_unexpected_eof},
        {"duplicate", :acp_unexpected_response}
      ] do
    test "rejects #{scenario} output", f do
      assert {:error, unquote(expected)} = execute(f, unquote(scenario)) |> Task.await(5_000)
    end
  end

  test "denies permission expansion and waits for cancellation and process cleanup", f do
    assert {:error, :acp_permission_required} = execute(f, "permission") |> Task.await(5_000)
    event = wait_event(f.request.run_id, "approval.requested")
    assert event.payload["kind"] == "execute"
    assert event.payload["title"] == "[REDACTED] command"

    assert event.public_summary ==
             "Agent requested permission; review is required: [REDACTED] command"

    refute inspect(event) =~ "must-not-persist"
    refute inspect(ActivityStream.list(f.request.run_id, 0)) =~ "must-not-persist"
    assert Enum.any?(requests(f), &(&1["method"] == "session/cancel"))
    refute Enum.any?(requests(f), &(get_in(&1, ["result", "outcome", "outcome"]) == "selected"))
    assert_owned_cleanup(f)
  end

  test "cancels a live prompt and never reports completion", f do
    task = execute(f, "wait")
    assert_receive {:client_ready, session}, 3_000
    wait_event(f.request.run_id, "tool.started")
    assert {:ok, %{exit_status: 0}} = Client.stop(session.process.handle)
    assert {:error, :acp_cancelled} = Task.await(task)
    assert_owned_cleanup(f)
  end

  test "rejects an unrelated durable session before prompting", f do
    f = %{f | request: %{f.request | attempt_id: Ecto.UUID.generate()}}
    assert {:error, :acp_owner_mismatch} = execute(f, "success") |> Task.await(5_000)
    refute Enum.any?(requests(f), &(&1["method"] == "session/prompt"))
    assert_owned_cleanup(f)
  end

  test "refuses a saved model mismatch before negotiation", f do
    mismatch = %{f | request: %{f.request | requested_model: "other-model"}}
    assert {:error, :acp_owner_mismatch} = execute(mismatch, "success") |> Task.await(5_000)
    refute Enum.any?(requests(f), &(&1["method"] == "initialize"))
    assert_owned_cleanup(f)
  end

  test "refuses an unrelated execution path before process creation", f do
    mismatch = %{f | request: %{f.request | worktree_path: f.environment.run_dir}}
    assert {:error, :acp_owner_mismatch} = execute(mismatch, "success") |> Task.await(5_000)
    refute Repo.exists?(from p in ProcessRecord, where: p.environment_id == ^f.environment.id)
  end

  test "orchestration owner loss records failure and cleans up without replay", f do
    task = execute(f, "wait")
    assert_receive {:client_ready, session}, 1_000
    wait_event(f.request.run_id, "tool.started")
    assert Task.shutdown(task, :brutal_kill) == nil
    wait_event(f.request.run_id, "session.failed")
    assert Repo.get!(AgentSession, f.stored.id).state == "failed"
    assert_owned_cleanup(f)
    refute Client.live_session?(session, %{process: :matching, session: :available})
    assert Enum.count(requests(f), &(&1["method"] == "session/prompt")) == 1
  end

  test "wake reconciliation retains the attached session without repeating its prompt", f do
    task = execute(f, "wait")
    assert_receive {:client_ready, _session}, 1_000
    wait_event(f.request.run_id, "tool.started")
    process = Repo.get_by!(ProcessRecord, environment_id: f.environment.id)

    assert {:ok, %{decisions: [{:ok, command}]}} =
             Cuckoding.Execution.Reconciler.run(
               run_ids: [f.request.run_id],
               gap_ms: 10_000,
               cycle_id: "acp-wake",
               inspector: Cuckoding.FakeRecoveryInspector,
               inspector_options: [
                 processes: %{process.pid => {:ok, process.start_identity}},
                 worktrees: %{f.environment.worktree_path => :present},
                 ports: %{}
               ]
             )

    assert command.result["outcome"] == "continue"
    assert Repo.get!(AgentSession, f.stored.id).state == "running"
    assert {:ok, _} = RunControl.control(f.request.run_id, "stop")
    assert {:error, :acp_cancelled} = Task.await(task)
    assert Enum.count(requests(f), &(&1["method"] == "session/prompt")) == 1
    assert_owned_cleanup(f)
  end

  test "a replacement client cannot replay a consumed attempt", f do
    assert {:ok, _} = execute(f, "success") |> Task.await(5_000)
    # A distinct session row cannot circumvent the attempt's durable reservation.
    {:ok, replacement} =
      Execution.create_agent_session(%{
        stage_attempt_id: f.request.attempt_id,
        adapter_key: "codex",
        requested_model: "fixture-model",
        effective_grant_json: %{}
      })

    assert {:error, :acp_prompt_already_started} =
             execute(%{f | stored: replacement}, "success") |> Task.await(5_000)

    refute Enum.any?(requests(f), &(&1["method"] == "session/prompt"))
    assert Repo.get!(AgentSession, replacement.id).state == "failed"
    assert_owned_cleanup(f)
  end

  test "pause preserves the same prompt and stop requires verified cleanup", f do
    task = execute(f, "wait")
    assert_receive {:client_ready, session}, 3_000
    wait_event(f.request.run_id, "tool.started")
    before = requests(f)
    assert {:ok, _} = LocalProcessRunner.pause(f.environment)
    status = inspect(:sys.get_status(session.process.handle))
    assert status =~ ":redacted"
    refute status =~ "fixture-secret-canary"
    assert {:ok, _} = LocalProcessRunner.resume(f.environment)
    assert {:ok, _} = Client.stop(session.process.handle)
    assert {:error, :acp_cancelled} = Task.await(task)
    assert Enum.count(before, &(&1["method"] == "session/prompt")) == 1
    assert Enum.count(requests(f), &(&1["method"] == "session/prompt")) == 1
    assert_owned_cleanup(f)
  end

  test "unresponsive cancellation ends in bounded owned cleanup", f do
    task = execute(f, "ignore-cancel")
    assert_receive {:client_ready, session}, 3_000
    wait_event(f.request.run_id, "tool.started")
    assert {:ok, _} = Client.stop(session.process.handle)
    assert {:error, :acp_cancelled} = Task.await(task)
    assert_owned_cleanup(f)
  end

  test "a completed turn can close an idle server through verified host termination", f do
    assert {:ok, result} = execute(f, "ignore-eof") |> Task.await(5_000)
    assert result.exit_status != 0
    assert result.stop_reason == "end_turn"
    assert result.protocol_completed?
    assert :ok = Cuckoding.Adapters.check_process_result(result)
    assert_owned_cleanup(f)
  end

  defp execute(f, scenario, extra \\ []) do
    owner = self()

    Task.async(fn ->
      RunControl.track(f.request.run_id, :workflow, fn ->
        execute_owned(f, scenario, extra, owner)
      end)
    end)
  end

  defp execute_owned(f, scenario, extra, owner) do
    launch = %{
      command: %{
        executable: "/usr/bin/ruby",
        args: [Path.expand("test/support/fixtures/acp_runtime.rb"), scenario]
      },
      environment: %{},
      environment_allowlist: [],
      timeout: 8_000,
      acp: %{
        adapter: Keyword.get(extra, :adapter, "codex"),
        mode: "read-only",
        session_params: %{}
      }
    }

    options =
      [
        runner: LocalProcessRunner,
        environment: f.environment,
        termination_grace_ms: 25,
        redact: ["fixture-secret-canary"]
      ] ++ extra

    grant = %Types.EffectiveGrant{requested: %{}, enforced: %{}, unenforced: %{}}

    with {:ok, session} <-
           RunControl.launch(f.request.run_id, fn ->
             Client.start(f.request, grant, launch, options)
           end) do
      send(owner, {:client_ready, session})
      if options[:wait_for_bind], do: receive(do: (:bind_session -> :ok))
      Client.execute(session.process.handle, f.stored)
    end
  end

  defp requests(f) do
    f.environment.worktree_path
    |> Path.join("acp-requests.jsonl")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  defp wait_event(run_id, type, attempts \\ 100)
  defp wait_event(_run_id, type, 0), do: flunk("Missing committed event #{type}")

  defp wait_event(run_id, type, attempts) do
    case Repo.one(
           from e in RunEvent, where: e.run_id == ^run_id and e.event_type == ^type, limit: 1
         ) do
      nil ->
        Process.sleep(10)
        wait_event(run_id, type, attempts - 1)

      event ->
        event
    end
  end

  defp assert_owned_cleanup(f) do
    for process <- Repo.all(from p in ProcessRecord, where: p.environment_id == ^f.environment.id) do
      assert process.state in ["exited", "failed"]
      assert LocalHostInspector.groups_empty?([process.pgid])
    end
  end

  defp fixture(root) do
    now = Cuckoding.Clock.wall_now()

    {:ok, project} =
      Projects.register(%{
        name: "ACP fixture",
        repo_path: root,
        default_branch: "main",
        workspace_root: root,
        port_range_start: 43_000,
        port_range_end: 43_100
      })

    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: String.duplicate("a", 64),
        config_json: %{"version" => 1},
        trusted_at: now
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: %{"stages" => [%{"key" => "spec", "role" => "spec_writer"}]},
        published_at: now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "ACP",
        concurrency_limit: 1
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: "ACP", position: 1})

    {:ok, %{result: %{"outcome" => "transitioned"}}} =
      Workflows.transition_task(task.id, "ready", "fixture:ready")

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: policy.id,
        plugin_snapshot_json: %{},
        branch: "feature/acp",
        base_sha: String.duplicate("a", 40)
      })

    {:ok, %{result: %{"outcome" => "transitioned"}}} =
      Execution.transition_run(run.id, "running", "fixture:running")

    {:ok, environment} =
      Execution.create_environment(%{
        run_id: run.id,
        runner_key: "local_process",
        kind: "local_process",
        worktree_path: Path.join(root, "worktree"),
        run_dir: Path.join(root, "run"),
        base_sha: run.base_sha,
        head_sha: run.base_sha,
        ports_json: %{},
        isolation_claims_json: %{"sandbox" => false}
      })

    {:ok, _} = LocalProcessRunner.prepare(environment, [])

    {:ok, attempt} =
      Execution.create_stage_attempt(%{
        run_id: run.id,
        stage_key: "spec",
        attempt: 1,
        role_key: "spec_writer",
        role_kind: "agent"
      })

    {:ok, stored} =
      Execution.create_agent_session(%{
        stage_attempt_id: attempt.id,
        adapter_key: "codex",
        requested_model: "fixture-model",
        effective_grant_json: %{}
      })

    request = %Types.StageRequest{
      project_id: project.id,
      board_id: board.id,
      task_id: task.id,
      run_id: run.id,
      stage_key: "spec",
      attempt_id: attempt.id,
      objective: "Return JSON",
      worktree_path: environment.worktree_path,
      run_dir: environment.run_dir,
      requested_model: "fixture-model",
      grant: %{},
      correlation_id: "fixture",
      idempotency_key: "fixture:prompt"
    }

    %{request: request, stored: stored, environment: environment}
  end
end
