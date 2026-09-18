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

  bootstrap_file =
    System.get_env("CUCKODING_BOOTSTRAP_FILE") ||
      raise "CUCKODING_BOOTSTRAP_FILE is required in production"

  secret_key_base =
    with {:ok, %{type: :regular, mode: mode, size: size}} when size <= 1_024 <-
           File.lstat(bootstrap_file),
         true <- Bitwise.band(mode, 0o077) == 0,
         {:ok, contents} <- File.read(bootstrap_file),
         [secret, _bootstrap] <- String.split(String.trim(contents), "\n", parts: 2),
         true <- byte_size(secret) >= 64 do
      secret
    else
      _other -> raise "CUCKODING_BOOTSTRAP_FILE must be a mode-0600 regular credential file"
    end

  config :cuckoding, Cuckoding.Repo, database: database_path, pool_size: 5
  config :cuckoding, CuckodingWeb.Endpoint, secret_key_base: secret_key_base
  config :cuckoding, :shell_bootstrap_file, bootstrap_file
end
