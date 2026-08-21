defmodule AgentDesk.Repo do
  use Ecto.Repo,
    otp_app: :agent_desk,
    adapter: Ecto.Adapters.SQLite3
end
