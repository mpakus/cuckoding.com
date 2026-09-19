defmodule Cuckoding.Adapters.StableStubsTest do
  use ExUnit.Case, async: true

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
    end

    assert is_nil(RuntimeConfiguration.warning("cursor_agent"))
    assert is_binary(RuntimeConfiguration.warning("opencode"))
    assert is_binary(RuntimeConfiguration.warning("custom_agent"))
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

  test "OpenCode stable stub rejects operational callbacks with visible details" do
    assert {:error,
            %Types.Error{
              code: :adapter_unavailable,
              category: :availability,
              retryable?: false,
              detail: detail
            }} = OpenCode.start(%{}, [])

    assert is_binary(detail)
    assert detail =~ "unavailable"

    assert {:error, %Types.Error{code: :adapter_unavailable}} =
             OpenCode.decode_event(%{}, [])
  end
end
