import Config

config :cuckoding, Cuckoding.Repo,
  database: Path.expand("../cuckoding_dev.db", __DIR__),
  pool_size: 5

config :cuckoding, CuckodingWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-for-cuckoding-0101-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:cuckoding, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:cuckoding, ~w(--watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/.*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      ~r"lib/cuckoding_web/(live|components)/.*\.(ex|heex)$"E,
      ~r"lib/cuckoding_web/router\.ex$"E
    ]
  ]

config :phoenix, :plug_init_mode, :runtime
config :phoenix, :stacktrace_depth, 20

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
