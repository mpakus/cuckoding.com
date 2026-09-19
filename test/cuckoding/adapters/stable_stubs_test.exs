defmodule Cuckoding.Adapters.StableStubsTest do
  use ExUnit.Case, async: true

  alias Cuckoding.Adapters.CursorAgent
  alias Cuckoding.Adapters.OpenCode
  alias Cuckoding.Adapters.RuntimeConfiguration
  alias Cuckoding.Adapters.Types

  test "project settings expose guarded and custom runtime connections without Claude secrets" do
    assert [
             {"Codex", "codex"},
             {"Claude Code", "claude_code"},
             {"Cursor Agent", "cursor_agent"},
             {"OpenCode", "opencode"},
             {"Custom Agent", "custom_agent"}
           ] = RuntimeConfiguration.options()

    for runtime <- ~w(cursor_agent opencode custom_agent) do
      assert {:ok, %{runtime: ^runtime, settings: settings}} =
               RuntimeConfiguration.validate(%{
                 "runtime" => runtime,
                 "executable_path" => "/usr/bin/true",
                 "api_key_helper" => "/must/not/be/used"
               })

      assert settings == %{"executable_path" => "/usr/bin/true"}
      assert is_binary(RuntimeConfiguration.warning(runtime))
    end
  end

  test "Cursor probe reports the real runtime but keeps it unavailable" do
    runner = fn _path, args, _options ->
      case args do
        ["--version"] ->
          {"2026.09.15-d2fe57e\n", 0}

        ["status", "--format", "json"] ->
          {~s({"isAuthenticated":true,"email":"private@example.test"}), 0}
      end
    end

    assert {:ok, probe} = CursorAgent.probe(path: "/bin/false", command_runner: runner)
    assert probe.version == "2026.09.15-d2fe57e"
    assert probe.authenticated?
    refute probe.available?
    assert probe.status == "unsupported_global_state_isolation"
    refute inspect(probe) =~ "private@example.test"

    assert {:ok, capabilities} = CursorAgent.capabilities([])
    refute capabilities.structured_output?
    refute capabilities.native_resume?
  end

  test "OpenCode distinguishes a desktop app from an installed CLI" do
    assert {:ok, probe} = OpenCode.probe(find_executable: fn _name -> nil end)
    refute probe.available?
    refute probe.authenticated?
    assert probe.status == "cli_not_installed"

    runner = fn _path, ["--version"], _options -> {"1.2.3\n", 0} end
    assert {:ok, detected} = OpenCode.probe(path: "/bin/false", command_runner: runner)
    assert detected.version == "1.2.3"
    refute detected.available?
    assert detected.status == "runtime_isolation_unverified"
  end

  test "both stable stubs reject operational callbacks with visible details" do
    for adapter <- [CursorAgent, OpenCode] do
      assert {:error,
              %Types.Error{
                code: :adapter_unavailable,
                category: :availability,
                retryable?: false,
                detail: detail
              }} = adapter.start(%{}, [])

      assert is_binary(detail)
      assert detail =~ "unavailable"

      assert {:error, %Types.Error{code: :adapter_unavailable}} =
               adapter.decode_event(%{}, [])
    end
  end
end
