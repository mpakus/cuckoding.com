import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :agent_desk, :data_root, Path.expand("../tmp/test-data", __DIR__)
config :agent_desk, :control_auth, mode: :test

config :agent_desk, AgentDesk.Repo,
  database: Path.expand("../tmp/test-data/agentdesk_test.sqlite3", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :agent_desk, AgentDeskWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Srt0r0AjeHVbcPJG89sQBhiRU7uEViKKTSX2tmOpk3cz1urLLGZkv3FeAaN7wOpl",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

config :agent_desk, :providers, use_fixtures: true
config :agent_desk, :provider_shutdown, interrupt_grace_ms: 50, terminate_grace_ms: 100
config :agent_desk, :provider_handshake_ms, 10_000

config :agent_desk, :search, adapter: :projection

config :agent_desk, :acp_registry, source: :snapshot

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
