defmodule Cuckoding.Adapters.CursorAgentTest do
  use ExUnit.Case, async: true

  alias Cuckoding.Adapters.CursorAgent
  alias Cuckoding.Adapters.Types

  defmodule FakeRunner do
    @moduledoc false
    def start(environment, command, options), do: {:ok, {environment, command, options}}
    def stop(handle), do: {:ok, %{handle: handle, exit_status: -1}}
  end

  setup do
    run_dir =
      Path.join(System.tmp_dir!(), "cuckoding-cursor-#{System.unique_integer([:positive])}")

    worktree = Path.join(run_dir, "worktree")
    executable = Path.join(run_dir, "cursor-agent")
    File.mkdir_p!(Path.join(run_dir, "agent"))
    File.mkdir_p!(worktree)
    File.write!(executable, "#!/bin/sh\nexit 1\n")
    File.chmod!(executable, 0o700)
    on_exit(fn -> File.rm_rf!(run_dir) end)

    request = %Types.StageRequest{
      project_id: Ecto.UUID.generate(),
      board_id: Ecto.UUID.generate(),
      task_id: Ecto.UUID.generate(),
      run_id: Ecto.UUID.generate(),
      stage_key: "implementation",
      attempt_id: Ecto.UUID.generate(),
      objective: "Implement the adapter",
      worktree_path: worktree,
      run_dir: run_dir,
      requested_model: "gpt-5",
      grant: %{
        "tools" => ["read", "write", "shell"],
        "deny_tools" => ["network", "mcp"],
        "approval_mode" => "default",
        "paths" => [worktree],
        "network" => "deny",
        "resource_limits" => %{"wall_ms" => 60_000}
      },
      plugins: [],
      correlation_id: Ecto.UUID.generate(),
      idempotency_key: "cursor:#{Ecto.UUID.generate()}"
    }

    {:ok,
     request: request,
     executable: executable,
     cursor_home: Path.join([run_dir, "agent", "cursor"])}
  end

  test "probe sees only the verified run-scoped login", %{
    executable: executable,
    cursor_home: cursor_home
  } do
    runner = fn _path, args, options ->
      environment = Map.new(options[:env])
      assert environment["AGENT_CLI_CREDENTIAL_STORE"] == "file"
      assert environment["HOME"] == Path.join(cursor_home, "home")
      assert environment["CURSOR_CONFIG_DIR"] == Path.join(cursor_home, "config")
      assert environment["CLAUDE_CONFIG_DIR"] == Path.join(cursor_home, "claude")

      case args do
        ["--version"] ->
          {"2026.09.15-d2fe57e\n", 0}

        ["status", "--format", "json"] ->
          {~s({"isAuthenticated":true,"email":"private@example.test"}), 0}
      end
    end

    assert {:error, %Types.Error{code: :run_scoped_config_required}} =
             CursorAgent.probe(path: executable, command_runner: runner)

    assert {:ok, unverified} =
             CursorAgent.probe(
               path: executable,
               cursor_home: cursor_home,
               command_runner: runner
             )

    refute unverified.authenticated?
    assert unverified.status == "run_scoped_auth_unverified"

    assert {:ok, verified} =
             CursorAgent.probe(
               path: executable,
               cursor_home: cursor_home,
               run_scoped_authenticated?: true,
               command_runner: runner
             )

    assert verified.available?
    assert verified.authenticated?
    refute inspect(verified) =~ "private@example.test"
  end

  test "discovers only valid models with the account-owned profile", %{
    executable: executable,
    cursor_home: cursor_home
  } do
    runner = fn ^executable, ["models"], options ->
      environment = Map.new(options[:env])
      assert environment["AGENT_CLI_CREDENTIAL_STORE"] == "file"
      assert environment["HOME"] == Path.join(cursor_home, "home")

      {"\e[2mAvailable models\e[0m\n\n\e[36mgpt-5\e[0m - GPT-5 (default)\n--unsafe - Unsafe\nclaude-sonnet-4 - Sonnet\n\nTip: use --model <id>\n",
       0}
    end

    assert {:ok,
            [
              %{"id" => "gpt-5", "label" => "GPT-5"},
              %{"id" => "claude-sonnet-4", "label" => "Sonnet"}
            ]} =
             CursorAgent.available_models(
               path: executable,
               cursor_home: cursor_home,
               command_runner: runner
             )
  end

  test "renders owner-only isolated config and a scoped launch", %{
    request: request,
    executable: executable,
    cursor_home: cursor_home
  } do
    assert {:ok, grant} = CursorAgent.render_config(request, [])
    assert grant.enforced["runtime_home"] == "run_owned"
    assert grant.enforced["mcp"] == "disabled"
    assert grant.enforced["network"] == "deny"

    config = File.read!(Path.join(cursor_home, "config/cli-config.json")) |> Jason.decode!()
    assert "Mcp(*:*)" in config["permissions"]["deny"]
    assert "WebFetch(*)" in config["permissions"]["deny"]
    assert "Shell(*)" in config["permissions"]["allow"]

    assert %{"mcpServers" => %{}} =
             cursor_home
             |> Path.join("home/.cursor/mcp.json")
             |> File.read!()
             |> Jason.decode!()

    for relative <- [
          "config/cli-config.json",
          "home/.cursor/sandbox.json",
          "home/.cursor/mcp.json"
        ] do
      assert Bitwise.band(File.stat!(Path.join(cursor_home, relative)).mode, 0o777) == 0o600
    end

    assert {:ok, spec} =
             CursorAgent.launch_spec(request,
               path: executable,
               run_scoped_authenticated?: true
             )

    assert Enum.take(spec.command.args, 4) == [
             "--print",
             "--output-format",
             "stream-json",
             "--sandbox"
           ]

    assert request.worktree_path in spec.command.args
    refute "--approve-mcps" in spec.command.args
    assert spec.environment["AGENT_CLI_CREDENTIAL_STORE"] == "file"
    assert spec.environment["HOME"] == Path.join(cursor_home, "home")
    assert spec.environment["CURSOR_CONFIG_DIR"] == Path.join(cursor_home, "config")
    assert spec.environment["CLAUDE_CONFIG_DIR"] == Path.join(cursor_home, "claude")
    assert spec.timeout == 60_000

    assert {:error, %Types.Error{code: :run_scoped_auth_required}} =
             CursorAgent.launch_spec(request, path: executable)

    assert {:error, %Types.Error{code: :plugins_unsupported}} =
             CursorAgent.render_config(%{request | plugins: [%{"kind" => "mcp"}]}, [])

    plan_request = put_in(request.grant["approval_mode"], "plan")
    assert {:ok, _grant} = CursorAgent.render_config(plan_request, [])

    plan_config =
      cursor_home |> Path.join("config/cli-config.json") |> File.read!() |> Jason.decode!()

    assert plan_config["permissions"]["allow"] == ["Read(**/*)"]
  end

  test "rejects project Cursor configuration that could start undeclared MCP or plugins", %{
    request: request
  } do
    File.mkdir_p!(Path.join(request.worktree_path, ".cursor"))
    File.write!(Path.join(request.worktree_path, ".cursor/mcp.json"), ~s({"mcpServers":{}}))

    assert {:error,
            %Types.Error{
              code: {:project_cursor_configuration_unsupported, ".cursor/mcp.json"}
            }} = CursorAgent.render_config(request, [])
  end

  test "rejects plugins discovered in the isolated login profile", %{
    request: request,
    cursor_home: cursor_home
  } do
    File.mkdir_p!(Path.join(cursor_home, "home/.cursor/plugins/example"))

    assert {:error,
            %Types.Error{
              code: {:run_cursor_plugins_unsupported, "home/.cursor/plugins"}
            }} = CursorAgent.render_config(request, [])
  end

  test "refuses a symlinked run configuration directory", %{request: request} do
    outside = request.run_dir <> "-outside"
    File.mkdir_p!(outside)
    File.ln_s!(outside, Path.join([request.run_dir, "agent", "cursor"]))
    on_exit(fn -> File.rm_rf!(outside) end)

    assert {:error, %Types.Error{code: :config_path_symlink}} =
             CursorAgent.render_config(request, [])
  end

  test "starts, cancels, resumes, and recovers through the host runner", %{
    request: request,
    executable: executable
  } do
    options = [
      path: executable,
      run_scoped_authenticated?: true,
      runner: FakeRunner,
      environment: %{id: "environment"}
    ]

    assert {:ok, session} = CursorAgent.start(request, options)
    assert session.process.runner == FakeRunner
    assert elem(session.process.handle, 2)[:timeout] == 60_000

    assert {:error, %Types.Error{code: :follow_up_requires_resume}} =
             CursorAgent.send(session, %{"summary" => "Continue"}, [])

    assert {:error, %Types.Error{code: :session_id_required}} =
             CursorAgent.resume(session, %{}, Keyword.put(options, :request, request))

    observed = %{session | external_session_id: "cursor-session-1"}
    resume_options = Keyword.put(options, :request, request)
    assert {:ok, resumed} = CursorAgent.resume(observed, %{}, resume_options)
    assert "cursor-session-1" in resumed.process.launch.command.args

    assert {:ok, ^observed} =
             CursorAgent.recover(observed, %{process: :matching, session: :available}, options)

    assert {:ok, _recovered} =
             CursorAgent.recover(observed, %{process: :gone, session: :available}, resume_options)

    assert {:ok, %{state: "cancelled"}} = CursorAgent.cancel(session, [])
  end

  test "normalizes the pinned fixture, redacts public output, and reports usage" do
    fixture = Path.expand("../../fixtures/agent/cursor-2026.09.15.stream.jsonl", __DIR__)
    rows = fixture |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    events =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {row, sequence} ->
        assert {:ok, event} =
                 CursorAgent.decode_event(row, sequence: sequence, redact: ["secret-canary"])

        event
      end)

    assert Enum.map(events, & &1.type) == [
             "session.started",
             "tool.requested",
             "tool.completed",
             "tool.requested",
             "tool.requested",
             "tool.completed",
             "session.completed"
           ]

    assert Enum.all?(events, &(&1.trust == :untrusted))

    assert {:ok, redacted} =
             CursorAgent.decode_event(
               %{
                 "type" => "result",
                 "subtype" => "success",
                 "result" => "secret-canary",
                 "usage" => %{}
               },
               redact: ["secret-canary"]
             )

    assert redacted.public_summary == "[REDACTED]"

    usage = rows |> List.last() |> Map.fetch!("usage")
    assert {:ok, reported} = CursorAgent.collect_usage(session(), usage: usage)
    assert reported.source == "provider"
    assert reported.input_tokens == 19_477
    assert reported.cache_read_tokens == 94_848
    assert is_nil(reported.cost_micros)

    assert {:error, %Types.Error{code: :unknown_event}} =
             CursorAgent.decode_event(%{"type" => "thinking", "text" => "hidden"}, [])
  end

  defp session do
    %Types.Session{
      adapter: "cursor_agent",
      session_id: "local",
      requested_model: nil,
      effective_grant: %Types.EffectiveGrant{requested: %{}, enforced: %{}, unenforced: %{}},
      state: "done"
    }
  end
end
