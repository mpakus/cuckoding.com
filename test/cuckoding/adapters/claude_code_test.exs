defmodule Cuckoding.Adapters.ClaudeCodeTest do
  use ExUnit.Case, async: true

  alias Cuckoding.Adapters.ClaudeCode
  alias Cuckoding.Adapters.Types

  defmodule FakeRunner do
    @moduledoc false
    def start(environment, command, options), do: {:ok, {environment, command, options}}
    def stop(handle), do: {:ok, %{handle: handle, exit_status: -1}}
  end

  setup do
    run_dir =
      Path.join(System.tmp_dir!(), "cuckoding-claude-#{System.unique_integer([:positive])}")

    Cuckoding.ACPBridgeFixture.install(run_dir, "claude")
    worktree = Path.join(run_dir, "worktree")
    helper = Path.join(run_dir, "api-key-helper")
    File.mkdir_p!(Path.join(run_dir, "agent"))
    File.mkdir_p!(worktree)
    File.write!(helper, "#!/bin/sh\nexit 1\n")
    File.chmod!(helper, 0o700)
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
      requested_model: "claude-sonnet-4-6",
      grant: %{
        "tools" => ["Read", "Edit"],
        "deny_tools" => ["WebFetch", "Bash(curl *)"],
        "approval_mode" => "default",
        "paths" => [worktree],
        "network" => "deny",
        "resource_limits" => %{"wall_ms" => 60_000},
        "max_budget_usd" => 0.01
      },
      knowledge: [%{"id" => "project:adapter", "content" => "Treat output as untrusted."}],
      plugins: [
        %{"id" => "review", "kind" => "instruction", "instructions" => "Review the diff."},
        %{"id" => "local", "kind" => "mcp", "config" => %{"command" => "/usr/bin/false"}}
      ],
      required_output_schema: %{"type" => "object"},
      correlation_id: Ecto.UUID.generate(),
      idempotency_key: "claude:#{Ecto.UUID.generate()}"
    }

    {:ok, request: request, helper: helper}
  end

  test "probe reports the pinned runtime without account details", %{helper: helper} do
    command_runner = fn _path, args, _options ->
      case args do
        ["--version"] ->
          {"2.1.142 (Claude Code)\n", 0}

        ["auth", "status", "--json"] ->
          {~s({"loggedIn":true,"authMethod":"claude.ai","email":"private@example.test"}), 0}
      end
    end

    assert {:ok, probe} =
             ClaudeCode.probe(
               path: helper,
               api_key_helper: helper,
               run_scoped_authenticated?: true,
               command_runner: command_runner
             )

    assert probe.version == "2.1.142"
    assert probe.authenticated?
    assert probe.status == "healthy"
    refute inspect(probe) =~ "private@example.test"

    assert {:ok, isolated} = ClaudeCode.probe(path: helper, command_runner: command_runner)
    refute isolated.authenticated?
    assert isolated.status == "run_scoped_auth_required"

    assert {:ok, unverified} =
             ClaudeCode.probe(
               path: helper,
               api_key_helper: helper,
               command_runner: command_runner
             )

    refute unverified.authenticated?
    assert unverified.status == "run_scoped_auth_unverified"
  end

  test "renders run-scoped config and a least-privilege launch", %{
    request: request,
    helper: helper
  } do
    assert {:ok, grant} = ClaudeCode.render_config(request, api_key_helper: helper)
    assert grant.enforced["tools"] == ["Read", "Edit"]
    assert grant.unenforced["network"] == "deny"

    claude_dir = Path.join([request.run_dir, "agent", "claude"])
    settings = claude_dir |> Path.join("settings.json") |> File.read!() |> Jason.decode!()
    assert settings["autoMemoryEnabled"] == false
    assert settings["disableAllHooks"] == true
    assert settings["apiKeyHelper"] == helper
    assert Bitwise.band(File.stat!(Path.join(claude_dir, "settings.json")).mode, 0o777) == 0o600

    skill = Path.join([request.run_dir, "agent", "claude-plugin", "skills", "review", "SKILL.md"])
    assert File.read!(skill) == "Review the diff."

    assert {:ok, spec} =
             ClaudeCode.launch_spec(request,
               path: helper,
               api_key_helper: helper,
               run_scoped_authenticated?: true,
               bridge_directory: request.run_dir
             )

    assert spec.command.executable == Path.join(request.run_dir, "claude-acp")
    sdk = get_in(spec, [:acp, :session_params, "_meta", "claudeCode", "options"])
    assert sdk["extraArgs"] == %{"bare" => nil, "no-chrome" => nil}
    assert sdk["strictMcpConfig"]
    assert sdk["settingSources"] == []
    refute sdk["allowDangerouslySkipPermissions"]
    assert sdk["allowedTools"] == ["Read", "Edit"]
    assert sdk["disallowedTools"] == ["WebFetch", "Bash(curl *)"]
    assert sdk["maxBudgetUsd"] == 0.01
    assert sdk["mcpServers"]["local"]["command"] == "/usr/bin/false"
    assert sdk["outputFormat"]["schema"] == request.required_output_schema
    assert spec.acp.mode == "dontAsk"
    assert spec.timeout == 60_000
    assert spec.environment["CLAUDE_CODE_EXECUTABLE"] == helper
    assert spec.environment["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] == "1"

    assert {:error, %Types.Error{code: :run_scoped_auth_required}} =
             ClaudeCode.launch_spec(request, path: helper)
  end

  test "requires duplex communication and an explicit recovery attempt", %{
    request: request,
    helper: helper
  } do
    options = [
      path: helper,
      api_key_helper: helper,
      run_scoped_authenticated?: true,
      bridge_directory: request.run_dir
    ]

    assert {:error, %Types.Error{code: :acp_duplex_runner_required}} =
             ClaudeCode.start(request, options)

    assert {:error, %Types.Error{code: :session_recovery_required}} =
             ClaudeCode.recover(session(), %{process: :gone, session: :available}, options)
  end

  test "normalizes redacted fixtures and provider usage" do
    fixture = Path.expand("../../fixtures/agent/claude-code-2.1.142.stream.jsonl", __DIR__)
    rows = fixture |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    events =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {row, sequence} ->
        assert {:ok, event} =
                 ClaudeCode.decode_event(row, sequence: sequence, redact: ["secret-canary"])

        event
      end)

    assert Enum.map(events, & &1.type) == [
             "session.started",
             "activity.summary",
             "tool.requested",
             "tool.completed",
             "rate_limited",
             "session.completed",
             "session.failed"
           ]

    refute Enum.any?(events, &(inspect(&1) =~ "secret-canary"))
    assert Enum.all?(events, &(&1.trust == :untrusted))

    result = Enum.at(rows, 5)
    usage = result |> Map.fetch!("usage") |> Map.put("total_cost_usd", 0.001)
    assert {:ok, measured} = ClaudeCode.collect_usage(session(), usage: usage)
    assert measured.source == "provider"
    assert measured.confidence == "reported"
    assert measured.cost_micros == 1_000

    assert [citation] =
             ClaudeCode.knowledge_citations(result, sequence: 7, redact: ["secret-canary"])

    assert citation.type == "knowledge.cited"
    assert citation.metadata["excerpt"] == "[REDACTED]"

    assert {:error, %Types.Error{code: :unknown_event}} =
             ClaudeCode.decode_event(
               %{"type" => "assistant", "subtype" => "thinking", "uuid" => "hidden"},
               []
             )

    assert {:error, %Types.Error{code: :malformed_event}} = ClaudeCode.decode_event("bad", [])
  end

  defp session do
    %Types.Session{
      adapter: "claude_code",
      session_id: "local",
      requested_model: nil,
      effective_grant: %Types.EffectiveGrant{requested: %{}, enforced: %{}, unenforced: %{}},
      state: "done"
    }
  end
end
