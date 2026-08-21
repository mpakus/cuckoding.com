defmodule AgentDesk.Providers.MCPInjection do
  @moduledoc """
  Per-session Agent Hub MCP overlay. Never writes the user's global provider config.
  """

  alias AgentDesk.Agents.Session
  alias AgentDesk.Providers.Fixture
  alias AgentDesk.Storage

  @spec write!(Session.t(), String.t()) :: String.t()
  def write!(%Session{} = session, token) when is_binary(token) do
    dir = Storage.session_dir(session.project_id, session.id)
    File.mkdir_p!(dir)
    path = Path.join(dir, "mcp.json")

    config = %{
      "mcpServers" => %{
        "agentdesk-hub" => %{
          "command" => Fixture.elixir_executable(),
          "args" =>
            Fixture.code_path_args() ++
              ["-e", "AgentDesk.MCP.Stdio.main(System.argv())", "--", "--session", session.id],
          "env" => %{
            "AGENTDESK_CAPABILITY_TOKEN" => token,
            "AGENTDESK_SESSION_ID" => session.id,
            "AGENTDESK_PROJECT_ID" => session.project_id
          }
        }
      }
    }

    File.write!(path, Jason.encode!(config))
    path
  end
end
