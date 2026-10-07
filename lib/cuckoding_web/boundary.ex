defmodule CuckodingWeb.Boundary do
  @moduledoc "Reject foreign hosts and browser origins even on a loopback listener."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("x-frame-options", "DENY")
      |> put_resp_header(
        "content-security-policy",
        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'; connect-src 'self' ws://127.0.0.1:#{port()} ws://localhost:#{port()}"
      )

    if conn.host in ["127.0.0.1", "localhost"] and conn.port == port() and
         Enum.all?(get_req_header(conn, "origin"), &allowed_origin?(URI.parse(&1))) and
         get_req_header(conn, "sec-fetch-site") != ["cross-site"] do
      conn
    else
      conn |> send_resp(403, "Open CCoding from its menu bar icon.") |> halt()
    end
  end

  def allowed_origin?(%URI{scheme: "http", host: host, port: port}),
    do: host in ["127.0.0.1", "localhost"] and port == port()

  def allowed_origin?(_), do: false

  def port do
    if CuckodingWeb.Endpoint.config(:server) do
      case CuckodingWeb.Endpoint.server_info(:http) do
        {:ok, {{127, 0, 0, 1}, port}} -> port
        _ -> 0
      end
    else
      CuckodingWeb.Endpoint.config(:http)[:port]
    end
  end
end
