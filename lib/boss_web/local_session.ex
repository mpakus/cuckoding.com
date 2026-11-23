defmodule BossWeb.LocalSession do
  @moduledoc false
  import Plug.Conn

  def init(action), do: action

  def call(conn, :origin) do
    allowed = BossWeb.Endpoint.config(:check_origin)
    origin = get_req_header(conn, "origin")
    port = BossWeb.Endpoint.config(:url)[:port]

    if conn.host in ["127.0.0.1", "localhost"] and conn.port == port and
         (origin == [] or (length(origin) == 1 and hd(origin) in allowed)) do
      conn
    else
      conn |> send_resp(403, "Forbidden") |> halt()
    end
  end
end
