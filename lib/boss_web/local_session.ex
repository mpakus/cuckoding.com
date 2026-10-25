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

  def call(conn, :require) do
    if Boss.LocalAccess.valid_session?(get_session(conn, :local_session)) do
      conn
    else
      conn |> Phoenix.Controller.redirect(to: "/unlock") |> halt()
    end
  end

  def on_mount(:default, _params, session, socket) do
    if Boss.LocalAccess.valid_session?(session["local_session"]) do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/unlock")}
    end
  end
end
