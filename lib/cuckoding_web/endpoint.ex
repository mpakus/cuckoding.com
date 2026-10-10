defmodule CuckodingWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :cuckoding

  @session_options [
    store: :cookie,
    key: "_ccoding_rebuild",
    signing_salt: "ccoding-session",
    encryption_salt: "ccoding-private",
    same_site: "Strict",
    http_only: true,
    max_age: 1_800
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug CuckodingWeb.Boundary

  if Mix.env() == :dev do
    plug Tidewave
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug :live_reload_csp
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader

    # Phoenix's development-only reload iframe contains its own inline script.
    defp live_reload_csp(%{path_info: ["phoenix", "live_reload", "frame" | _]} = conn, _) do
      Plug.Conn.update_resp_header(conn, "content-security-policy", "", fn csp ->
        String.replace(csp, "script-src 'self'", "script-src 'self' 'unsafe-inline'")
      end)
    end

    defp live_reload_csp(conn, _), do: conn
  end

  plug Plug.Static,
    at: "/",
    from: :cuckoding,
    gzip: true,
    only: CuckodingWeb.static_paths(),
    only_matching: ["favicon-"]

  plug Plug.RequestId
  plug Plug.Parsers, parsers: [:urlencoded, :json], pass: [], json_decoder: Jason, length: 8_192
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug CuckodingWeb.Router
end
