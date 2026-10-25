import Config

config :boss, BossWeb.Endpoint,
  code_reloader: true,
  debug_errors: false,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:boss, ~w(--sourcemap=inline --watch)]},
    npm: ["run", "watch", cd: Path.expand("../assets", __DIR__)]
  ]

config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, enable_expensive_runtime_checks: true
