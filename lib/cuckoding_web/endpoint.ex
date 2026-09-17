defmodule CuckodingWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :cuckoding

  @session_options [
    store: :cookie,
    key: "_cuckoding",
    signing_salt: "cuckoding-session",
    same_site: "Strict",
    http_only: true,
    max_age: 3600
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :cuckoding,
    gzip: not code_reloading?,
    only: CuckodingWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug CuckodingWeb.CorrelationId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug CuckodingWeb.Router
end
