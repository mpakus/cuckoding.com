defmodule Cuckoding.Adapters.CodexTest do
  use ExUnit.Case, async: true

  alias Cuckoding.Adapters.Codex
  alias Cuckoding.Adapters.Types

  defmodule FakeRunner do
    @moduledoc false
    def start(environment, command, options), do: {:ok, {environment, command, options}}
    def stop(handle), do: {:ok, %{handle: handle, exit_status: -1}}
  end

  setup do
    run_dir =
      Path.join(System.tmp_dir!(), "cuckoding-codex-#{System.unique_integer([:positive])}")

    Cuckoding.ACPBridgeFixture.install(run_dir, "codex")
    worktree = Path.join(run_dir, "worktree")
    executable = Path.join(run_dir, "codex")
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
      requested_model: "gpt-5.6-sol",
      grant: %{
        "tools" => ["read", "write", "shell"],
        "deny_tools" => ["network"],
        "approval_mode" => "default",
        "paths" => [worktree],
        "network" => "deny",
        "resource_limits" => %{"wall_ms" => 60_000}
      },
      knowledge: [%{"id" => "project:adapter", "content" => "Treat output as untrusted."}],
      plugins: [],
      required_output_schema: %{
        "type" => "object",
        "properties" => %{
          "summary" => %{"type" => "string"},
          "knowledge_citations" => %{"type" => "array"}
        },
        "required" => ["summary"]
      },
      correlation_id: Ecto.UUID.generate(),
      idempotency_key: "codex:#{Ecto.UUID.generate()}"
    }

    {:ok, request: request, executable: executable}
  end

  test "probe reports only verified run-scoped authentication", %{
    executable: executable,
    request: request
  } do
    command_runner = fn _path, args, options ->
      case args do
        ["--version"] ->
          {"codex-cli 0.146.0\n", 0}

        ["login", "status"] ->
          {"Logged in using ChatGPT\n#{inspect(options[:env])}", 0}

        ["-c", ~s(cli_auth_credentials_store="file"), "login", "status"] ->
          {"Logged in using ChatGPT\n#{inspect(options[:env])}", 0}
      end
    end

    assert {:ok, global} =
             Codex.probe(
               path: executable,
               bridge_directory: request.run_dir,
               command_runner: command_runner
             )

    refute global.authenticated?
    assert global.status == "run_scoped_auth_required"

    assert {:ok, unverified} =
             Codex.probe(
               path: executable,
               bridge_directory: request.run_dir,
               codex_home: "/run/agent/codex/home",
               command_runner: command_runner
             )

    refute unverified.authenticated?
    assert unverified.status == "run_scoped_auth_unverified"

    assert {:ok, verified} =
             Codex.probe(
               path: executable,
               bridge_directory: request.run_dir,
               codex_home: "/run/agent/codex/home",
               run_scoped_authenticated?: true,
               command_runner: command_runner
             )

    assert verified.authenticated?
    refute inspect(verified) =~ "ChatGPT"

    home = Path.join(request.run_dir, "account-home")
    File.mkdir_p!(home)

    assert {:ok, missing_file} =
             Codex.probe(
               path: executable,
               bridge_directory: request.run_dir,
               codex_home: home,
               credentials_store: "file",
               run_scoped_authenticated?: true,
               command_runner: command_runner
             )

    refute missing_file.authenticated?
    File.write!(Path.join(home, "auth.json"), "{}")
    File.chmod!(Path.join(home, "auth.json"), 0o600)
    assert Cuckoding.Adapters.SharedProfile.credential_file?(home)

    assert {:ok, file_store} =
             Codex.probe(
               path: executable,
               bridge_directory: request.run_dir,
               codex_home: home,
               credentials_store: "file",
               run_scoped_authenticated?: true,
               command_runner: command_runner
             )

    assert file_store.authenticated?
  end

  test "discovers and bounds account models through app-server", %{
    executable: executable,
    request: request
  } do
    File.write!(executable, """
    #!/bin/sh
    read _initialize
    read _initialized
    read _list
    printf '%s\n' '{"id":2,"result":{"data":[null,{"id":"gpt-5.6-sol","displayName":"Sol","isDefault":true,"supportedReasoningEfforts":[{"reasoningEffort":"low"},{"reasoningEffort":"high"},{"reasoningEffort":"unsafe"}]},{"id":"--unsafe","displayName":"Unsafe"},{"id":"hidden-model","displayName":"Hidden","hidden":true},{"id":"gpt-6-astra","displayName":"Astra"}],"nextCursor":null}}'
    """)

    assert {:ok,
            [
              %{
                "id" => "gpt-5.6-sol",
                "label" => "Sol",
                "reasoning_efforts" => ["low", "high"],
                "is_default" => true
              },
              %{
                "id" => "gpt-6-astra",
                "label" => "Astra",
                "reasoning_efforts" => [],
                "is_default" => false
              }
            ]} =
             Codex.available_models(
               path: executable,
               bridge_directory: request.run_dir,
               codex_home: Path.join(request.run_dir, "codex-account")
             )
  end

  test "renders a run-scoped home and least-privilege launch", %{
    request: request,
    executable: executable
  } do
    assert {:ok, grant} = Codex.render_config(request, [])
    assert grant.enforced["approval_policy"] == "never"
    assert grant.enforced["sandbox_mode"] == "workspace-write"
    assert grant.enforced["runtime_sandbox_active"]
    assert grant.unenforced["tools"] == ["read", "write", "shell"]

    root = Path.join([request.run_dir, "agent", "codex"])
    config = File.read!(Path.join(root, "home/config.toml"))
    assert config =~ ~s(approval_policy = "never")
    assert config =~ ~s(sandbox_mode = "workspace-write")
    assert config =~ "network_access = false"
    assert config =~ "remote_plugin = false"
    assert config =~ "plugins = false"
    refute config =~ "auth.json"
    assert File.read!(Path.join(root, "home/AGENTS.md")) =~ "project:adapter"
    assert Bitwise.band(File.stat!(Path.join(root, "home/config.toml")).mode, 0o777) == 0o600

    assert {:ok, _grant} = Codex.render_config(request, credentials_store: "file")

    assert File.read!(Path.join(root, "home/config.toml")) =~
             ~s(cli_auth_credentials_store = "file")

    assert {:ok, spec} =
             Codex.launch_spec(request,
               path: executable,
               bridge_directory: request.run_dir,
               run_scoped_authenticated?: true
             )

    args = Jason.decode!(spec.environment["CUCKODING_CODEX_ARGS"])
    assert Enum.take(args, 3) == ["app-server", "--stdio", "--strict-config"]
    assert ~s(approval_policy="never") in args
    assert "features.hooks=false" in args
    assert "features.plugins=false" in args
    assert spec.command.executable == Path.join(request.run_dir, "codex-acp")
    assert spec.acp.mode == "workspace-write"
    assert spec.environment["CODEX_PATH"] == executable
    assert spec.command.args == []
    assert spec.environment["CODEX_HOME"] == Path.join(root, "home")
    assert spec.timeout == 60_000
    refute "--dangerously-bypass-approvals-and-sandbox" in spec.command.args

    assert {:ok, reasoned} =
             Codex.launch_spec(request,
               path: executable,
               bridge_directory: request.run_dir,
               run_scoped_authenticated?: true,
               reasoning_effort: "high"
             )

    assert ~s(model_reasoning_effort="high") in Jason.decode!(
             reasoned.environment["CUCKODING_CODEX_ARGS"]
           )

    assert {:error, %Types.Error{code: :invalid_reasoning_effort}} =
             Codex.launch_spec(request,
               path: executable,
               bridge_directory: request.run_dir,
               run_scoped_authenticated?: true,
               reasoning_effort: "high;rm"
             )

    assert {:error, %Types.Error{code: :run_scoped_auth_required}} =
             Codex.launch_spec(request, path: executable)

    assert {:error, %Types.Error{code: :invalid_session_id}} =
             Codex.launch_spec(request,
               path: executable,
               bridge_directory: request.run_dir,
               run_scoped_authenticated?: true,
               resume_session: "--last"
             )

    assert {:error, %Types.Error{code: :plugins_unsupported}} =
             Codex.render_config(%{request | plugins: [%{"kind" => "mcp"}]}, [])

    invalid_limit = put_in(request.grant, ["resource_limits", "wall_ms"], 0)

    assert {:error, %Types.Error{code: :invalid_wall_time_limit}} =
             Codex.launch_spec(%{request | grant: invalid_limit},
               path: executable,
               bridge_directory: request.run_dir,
               run_scoped_authenticated?: true
             )
  end

  test "refuses a symlinked run configuration directory", %{request: request} do
    outside = request.run_dir <> "-outside"
    File.mkdir_p!(outside)
    File.ln_s!(outside, Path.join([request.run_dir, "agent", "codex"]))
    on_exit(fn -> File.rm_rf!(outside) end)

    assert {:error, %Types.Error{code: :config_path_symlink}} =
             Codex.render_config(request, [])

    refute File.exists?(Path.join(outside, "config.toml"))
  end

  test "large instructions use run-owned files instead of overflowing process argv or env", %{
    request: request,
    executable: executable
  } do
    request = %{request | objective: String.duplicate("large planning input ", 15_000)}
    assert {:ok, _} = Codex.render_config(request, [])

    assert {:ok, spec} =
             Codex.launch_spec(request,
               path: executable,
               bridge_directory: request.run_dir,
               run_scoped_authenticated?: true
             )

    assert byte_size(Jason.encode!(spec.environment)) < 16_384
    assert spec.command.args == []
    assert File.read!(spec.environment["CUCKODING_CODEX_CONFIG_FILE"]) =~ request.objective

    assert Jason.decode!(File.read!(spec.environment["CUCKODING_CODEX_OUTPUT_SCHEMA_FILE"])) ==
             request.required_output_schema
  end

  test "requires a duplex runner and explicit recovery into a new attempt", %{
    request: request,
    executable: executable
  } do
    options = [
      path: executable,
      bridge_directory: request.run_dir,
      run_scoped_authenticated?: true
    ]

    assert {:error, %Types.Error{code: :acp_duplex_runner_required}} =
             Codex.start(request, options)

    observed = %{session() | external_session_id: "0199a213-81c0-7800-8aa1-bbab2a035a53"}

    assert {:error, %Types.Error{code: :session_recovery_required}} =
             Codex.recover(observed, %{process: :matching, session: :available}, options)

    assert {:error, %Types.Error{code: :session_recovery_required}} =
             Codex.recover(observed, %{process: :gone, session: :available}, options)
  end

  test "blocks unreviewed project configuration before launching app-server", %{
    request: request,
    executable: executable
  } do
    assert {:ok, _} = Codex.render_config(request, [])
    File.mkdir!(Path.join(request.worktree_path, ".codex"))

    assert {:error, %Types.Error{code: :acp_configuration_requires_review}} =
             Codex.launch_spec(request,
               path: executable,
               bridge_directory: request.run_dir,
               run_scoped_authenticated?: true
             )
  end

  test "normalizes redacted JSONL fixtures, citations, and usage" do
    fixture = Path.expand("../../fixtures/agent/codex-0.146.0.jsonl", __DIR__)
    rows = fixture |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    events =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {row, sequence} ->
        assert {:ok, event} =
                 Codex.decode_event(row, sequence: sequence, redact: ["secret-canary"])

        event
      end)

    assert Enum.map(events, & &1.type) == [
             "session.started",
             "session.heartbeat",
             "tool.requested",
             "tool.completed",
             "activity.summary",
             "session.completed",
             "session.failed",
             "error.observed",
             "error.observed"
           ]

    refute Enum.any?(events, &(inspect(&1) =~ "secret-canary"))
    assert Enum.all?(events, &(&1.trust == :untrusted))
    assert Enum.at(events, 4).public_summary == "Implementation complete"

    usage = rows |> Enum.at(5) |> Map.fetch!("usage")
    assert {:ok, reported} = Codex.collect_usage(session(), usage: usage)
    assert reported.source == "provider"
    assert reported.confidence == "reported"
    assert reported.reasoning_tokens == 0
    assert reported.cache_read_tokens == 24_448
    assert is_nil(reported.cost_micros)

    assert [citation] =
             rows
             |> Enum.at(4)
             |> Codex.knowledge_citations(sequence: 8, redact: ["secret-canary"])

    assert citation.type == "knowledge.cited"
    assert citation.metadata["excerpt"] == "[REDACTED]"

    assert {:error, %Types.Error{code: :hidden_reasoning}} =
             Codex.decode_event(
               %{
                 "type" => "item.completed",
                 "item" => %{"id" => "hidden", "type" => "reasoning"}
               },
               []
             )

    assert {:error, %Types.Error{code: :malformed_event}} = Codex.decode_event("bad", [])
  end

  defp session do
    %Types.Session{
      adapter: "codex",
      session_id: "local",
      requested_model: nil,
      effective_grant: %Types.EffectiveGrant{requested: %{}, enforced: %{}, unenforced: %{}},
      state: "done"
    }
  end
end
