defmodule AgentDesk.Providers.EnvironmentCompatibilityTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Agents.Session
  alias AgentDesk.Providers.Claude
  alias AgentDesk.Providers.Codex.AppServer
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Cursor
  alias AgentDesk.Providers.OpenCode
  alias AgentDesk.Providers.SDK

  test "first-party command specs declare provider-specific environment policies" do
    session = %Session{settings: %{}}

    assert {:ok, codex} = AppServer.command_spec(session, fixture: false)
    assert "OPENAI_API_KEY" in codex.env_passthrough
    refute "ANTHROPIC_API_KEY" in codex.env_passthrough

    assert {:ok, claude} = Claude.command_spec(session, fixture: false)
    assert "ANTHROPIC_API_KEY" in claude.env_passthrough
    refute "OPENAI_API_KEY" in claude.env_passthrough

    assert {:ok, cursor} =
             Cursor.command_spec(session, fixture: false, executable: "cursor-agent")

    assert cursor.env_passthrough == ["CURSOR_API_KEY"]

    assert {:ok, opencode} = OpenCode.command_spec(session, fixture: false)
    assert "OPENCODE_API_KEY" in opencode.env_passthrough
  end

  test "SDK command config accepts a validated environment allowlist" do
    session = %Session{
      settings: %{
        "sdk_executable" => System.find_executable("elixir"),
        "sdk_env_allowlist" => "VENDOR_TOKEN\nVENDOR_BASE_URL"
      }
    }

    assert {:ok, spec} = SDK.command_spec(session, fixture: false)
    assert spec.env_passthrough == ["VENDOR_TOKEN", "VENDOR_BASE_URL"]
  end

  test "SDK command config rejects malformed environment names" do
    session = %Session{
      settings: %{
        "sdk_executable" => System.find_executable("elixir"),
        "sdk_env_allowlist" => ["VALID_NAME", "INVALID=value"]
      }
    }

    assert {:error, :invalid_env_passthrough} = SDK.command_spec(session, fixture: false)
  end

  test "command inspection never renders explicit environment values" do
    spec = %CommandSpec{
      executable: "provider",
      env: %{"VENDOR_TOKEN" => "secret-value-that-must-not-be-logged"}
    }

    refute inspect(spec) =~ "secret-value-that-must-not-be-logged"
  end
end
