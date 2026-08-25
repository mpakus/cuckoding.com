defmodule AgentDesk.Providers.ClaudeTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Agents.Session
  alias AgentDesk.Providers.Claude

  test "new sessions do not pass a resume flag" do
    session = %Session{settings: %{}}

    assert {:ok, spec} = Claude.command_spec(session, fixture: false)
    refute "--resume" in spec.args
  end

  test "persisted provider sessions are loaded through Claude's documented resume flag" do
    session = %Session{
      settings: %{},
      provider_session_id: "550e8400-e29b-41d4-a716-446655440000"
    }

    assert {:ok, spec} = Claude.command_spec(session, fixture: false)

    assert Enum.chunk_every(spec.args, 2, 1, :discard)
           |> Enum.member?(["--resume", session.provider_session_id])

    assert {:ok, "", _state} =
             Claude.encode({:resume, session.provider_session_id}, Claude.init_decode())
  end
end
