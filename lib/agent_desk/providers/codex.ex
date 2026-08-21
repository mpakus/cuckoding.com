defmodule AgentDesk.Providers.Codex do
  @moduledoc """
  Codex adapter entry. App Server is primary; `exec --json` is the one-shot fallback.
  """

  alias AgentDesk.Providers.Codex.AppServer
  alias AgentDesk.Providers.Codex.Exec

  defdelegate key(), to: AppServer
  defdelegate display_name(), to: AppServer
  defdelegate capabilities(), to: AppServer
  defdelegate probe(opts), to: AppServer
  defdelegate command_spec(session, opts), to: AppServer
  defdelegate init_decode(), to: AppServer
  defdelegate decode_line(line, state), to: AppServer
  defdelegate encode(action, state), to: AppServer

  @spec fallback :: module()
  def fallback, do: Exec
end
