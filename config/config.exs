import Config

config :cuckoding,
  clock: Cuckoding.SystemClock,
  command_handler: Cuckoding.Execution.UnconfiguredCommandHandler,
  environment: config_env(),
  ecto_repos: [Cuckoding.Repo],
  recovery_inspector: Cuckoding.Execution.LocalHostInspector

config :cuckoding, :power_manager,
  enabled: true,
  prevent_display_sleep: false,
  tick_ms: 5_000,
  tolerance_ms: 1_000

config :cuckoding, Cuckoding.Repo,
  adapter: Ecto.Adapters.SQLite3,
  busy_timeout: 5_000,
  default_transaction_mode: :immediate,
  foreign_keys: :on,
  journal_mode: :wal,
  synchronous: :normal

config :cuckoding, CuckodingWeb.Endpoint,
  url: [host: "127.0.0.1"],
  http: [ip: {127, 0, 0, 1}],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CuckodingWeb.ErrorHTML, json: CuckodingWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Cuckoding.PubSub,
  live_view: [signing_salt: "cuckoding-live"]

config :phoenix_live_view,
  root_tag_attribute: "phx-r"

config :esbuild,
  version: "0.25.4",
  cuckoding: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.2.1",
  cuckoding: [
    args: ~w(--input=assets/css/app.css --output=priv/static/assets/css/app.css),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :default_formatter,
  format: "time=$time level=$level $metadata$message\n",
  metadata: [:request_id, :correlation_id, :recovered_commands, :dispatched_commands]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
