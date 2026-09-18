defmodule CuckodingWeb.LoopbackOnly do
  @moduledoc false

  import Plug.Conn

  def init(options), do: options

  def call(conn, _options) do
    if conn.remote_ip == {127, 0, 0, 1} and conn.host == "127.0.0.1" and valid_origin?(conn) do
      conn
    else
      conn |> send_resp(:forbidden, "forbidden") |> halt()
    end
  end

  defp valid_origin?(conn) do
    case get_req_header(conn, "origin") do
      [] -> true
      [origin] -> origin == "http://127.0.0.1:#{conn.port}"
      _other -> false
    end
  end
end
