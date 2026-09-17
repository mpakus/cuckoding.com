import Config

port = String.to_integer(System.get_env("CUCKODING_PORT", "4000"))

config :cuckoding, CuckodingWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: port],
  url: [host: "127.0.0.1", port: port, scheme: "http"],
  server: System.get_env("PHX_SERVER") in ["1", "true"]

if config_env() == :prod do
  database_path =
    System.get_env("CUCKODING_DATABASE_PATH") ||
      raise "CUCKODING_DATABASE_PATH is required in production"

  secret_key_base =
    System.get_env("CUCKODING_SECRET_KEY_BASE") ||
      raise "CUCKODING_SECRET_KEY_BASE is required in production"

  config :cuckoding, Cuckoding.Repo, database: database_path, pool_size: 5
  config :cuckoding, CuckodingWeb.Endpoint, secret_key_base: secret_key_base
end
