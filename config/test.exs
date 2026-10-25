import Config

config :boss, Boss.Repo, pool: Ecto.Adapters.SQL.Sandbox
config :boss, BossWeb.Endpoint, server: false
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, enable_expensive_runtime_checks: true
config :phoenix, sort_verified_routes_query_params: true
