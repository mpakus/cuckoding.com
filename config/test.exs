import Config

config :cuckoding, Cuckoding.Repo,
  database: Path.expand("../cuckoding_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :cuckoding, CuckodingWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test-only-secret-key-base-for-cuckoding-0101-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  server: false

config :logger, level: :warning
config :cuckoding, :power_manager, enabled: false
config :cuckoding, :resource_sampler, enabled: false
config :cuckoding, :plugin_registry, enabled: false
config :cuckoding, :provider_account_root, Path.expand("../tmp/test-provider-accounts", __DIR__)
config :phoenix, :plug_init_mode, :runtime
config :phoenix, sort_verified_routes_query_params: true
config :phoenix_live_view, enable_expensive_runtime_checks: true
