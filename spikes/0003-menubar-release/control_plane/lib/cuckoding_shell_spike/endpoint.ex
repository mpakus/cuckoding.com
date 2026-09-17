defmodule CuckodingShellSpike.Endpoint do
  use Phoenix.Endpoint, otp_app: :cuckoding_shell_spike

  @session_options [
    store: :cookie,
    key: "_cuckoding_shell_spike",
    signing_salt: "shell-spike-session",
    same_site: "Strict",
    http_only: true,
    max_age: 3600
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false
  )

  plug(CuckodingShellSpike.HostGuard)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.Session, @session_options)
  plug(CuckodingShellSpike.Router)
end
