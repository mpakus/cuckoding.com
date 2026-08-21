defmodule AgentDesk.Search.Xerj.Discovery do
  @moduledoc false

  @spec executable() :: String.t() | nil
  def executable do
    configured = Application.get_env(:agent_desk, :search, [])[:xerj_executable]
    configured || System.find_executable("xerj")
  end
end
