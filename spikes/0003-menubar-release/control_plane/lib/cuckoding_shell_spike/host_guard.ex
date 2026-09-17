defmodule CuckodingShellSpike.HostGuard do
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, _options) do
    if conn.host == "127.0.0.1" do
      conn
    else
      conn |> send_resp(400, "invalid host") |> halt()
    end
  end
end
