import Config
config :cuckoding, :testing, true
config :cuckoding, :data_dir, Path.expand("../.ccoding/test", __DIR__)
config :cuckoding, :dispatcher, false

config :cuckoding, CuckodingWeb.Endpoint,
  server: false,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("test-only-", 8)

config :cuckoding, Cuckoding.Repo,
  database: Path.expand("../.ccoding/test/foundation.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox
