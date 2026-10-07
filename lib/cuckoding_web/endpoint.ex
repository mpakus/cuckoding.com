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
  plug Plug.Static, at: "/", from: :cuckoding, gzip: true, only: CuckodingWeb.static_paths()
  plug Plug.RequestId
  plug Plug.Parsers, parsers: [:urlencoded, :json], pass: [], json_decoder: Jason, length: 8_192
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug CuckodingWeb.Router
end
