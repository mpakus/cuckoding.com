import Config
config :cuckoding, ecto_repos: [Cuckoding.Repo]

config :cuckoding, Cuckoding.Repo,
  journal_mode: :wal,
  foreign_keys: :on,
  busy_timeout: 5_000,
  pool_size: 2,
  default_transaction_mode: :immediate,
  log: false

config :cuckoding, CuckodingWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "127.0.0.1"],
  http: [ip: {127, 0, 0, 1}, port: 0],
  check_origin: {CuckodingWeb.Boundary, :allowed_origin?, []},
  render_errors: [
    formats: [html: CuckodingWeb.ErrorHTML, json: CuckodingWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Cuckoding.PubSub,
  live_view: [signing_salt: "ccoding-live"]

config :phoenix, :json_library, Jason
config :phoenix, :filter_parameters, ["token", "session_id", "authorization", "cookie", "secret"]
config :logger, level: :warning

config :esbuild,
  version: "0.25.4",
  cuckoding: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "4.3.0",
  cuckoding: [
    args: ~w(--input=assets/css/app.css --output=priv/static/assets/css/app.css),
    cd: Path.expand("..", __DIR__)
  ]

import_config "#{config_env()}.exs"
