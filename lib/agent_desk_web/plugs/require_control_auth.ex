defmodule AgentDeskWeb.Plugs.RequireControlAuth do
  @moduledoc false

  import Plug.Conn

  alias AgentDesk.Security.ControlAuth

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    if ControlAuth.authorized_session?(get_session(conn)) do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(:unauthorized, "Desktop control authorization required.")
      |> halt()
    end
  end
end
