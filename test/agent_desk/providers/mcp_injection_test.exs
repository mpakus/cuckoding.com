defmodule AgentDesk.Providers.MCPInjectionTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias AgentDesk.Agents.Session
  alias AgentDesk.Providers.MCPInjection
  alias AgentDesk.Storage

  test "acp_servers maps mcp.json into ACP session/new entries" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "agentdesk-mcp-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    path = Path.join(dir, "mcp.json")

    File.write!(
      path,
      Jason.encode!(%{
        "mcpServers" => %{
          "agentdesk-hub" => %{
            "command" => "elixir",
            "args" => ["-e", "ok"],
            "env" => %{"AGENTDESK_CAPABILITY_TOKEN" => "tok"}
          }
        }
      })
    )

    [server] = MCPInjection.acp_servers(path)
    assert server["name"] == "agentdesk-hub"
    assert server["command"] == "elixir"
    assert %{"name" => "AGENTDESK_CAPABILITY_TOKEN", "value" => "tok"} in server["env"]
  end

  test "writes token-bearing overlays atomically in private paths" do
    session = %Session{
      id: Ecto.UUID.generate(),
      project_id: Ecto.UUID.generate(),
      provider: "remote"
    }

    dir = Storage.session_dir(session.project_id, session.id)
    on_exit(fn -> File.rm_rf(Storage.project_dir(session.project_id)) end)

    mcp_path = MCPInjection.write!(session, "first-private-token")
    connect_path = MCPInjection.connect_env_path(session)

    assert file_mode(dir) == 0o700
    assert file_mode(mcp_path) == 0o600
    assert file_mode(connect_path) == 0o600
    assert File.read!(mcp_path) =~ "first-private-token"
    assert File.read!(connect_path) =~ "first-private-token"
    assert Path.wildcard(Path.join(dir, "*.tmp-*")) == []

    assert ^mcp_path = MCPInjection.write!(session, "replacement-private-token")
    assert file_mode(mcp_path) == 0o600
    assert file_mode(connect_path) == 0o600
    refute File.read!(mcp_path) =~ "first-private-token"
    assert File.read!(mcp_path) =~ "replacement-private-token"
    assert Path.wildcard(Path.join(dir, "*.tmp-*")) == []
  end

  test "does not duplicate attach credentials for spawned providers" do
    session = %Session{
      id: Ecto.UUID.generate(),
      project_id: Ecto.UUID.generate(),
      provider: "codex"
    }

    on_exit(fn -> File.rm_rf(Storage.project_dir(session.project_id)) end)

    _ = MCPInjection.write!(session, "spawned-provider-token")
    refute File.exists?(MCPInjection.connect_env_path(session))
  end

  test "rejects symlinked private path ancestors" do
    session = %Session{
      id: Ecto.UUID.generate(),
      project_id: Ecto.UUID.generate(),
      provider: "remote"
    }

    outside =
      Path.join(
        System.tmp_dir!(),
        "agentdesk-mcp-outside-#{System.unique_integer([:positive, :monotonic])}"
      )

    project_dir = Storage.project_dir(session.project_id)
    File.mkdir_p!(Path.dirname(project_dir))
    File.mkdir_p!(outside)
    File.ln_s!(outside, project_dir)

    on_exit(fn ->
      File.rm(project_dir)
      File.rm_rf(outside)
    end)

    assert_raise File.Error, fn ->
      MCPInjection.write!(session, "must-not-follow-symlink")
    end

    refute File.exists?(Path.join(outside, "sessions"))
  end

  defp file_mode(path) do
    File.stat!(path).mode &&& 0o777
  end
end
