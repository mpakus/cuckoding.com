import Config

port = System.fetch_env!("CUCKODING_PORT") |> String.to_integer()

secret_key_base =
  if config_env() == :test do
    String.duplicate("test-secret-", 6)
  else
    bootstrap_path = System.fetch_env!("CUCKODING_BOOTSTRAP_FILE")
    [secret_key_base, _bootstrap] = bootstrap_path |> File.read!() |> String.split("\n", parts: 2)
    secret_key_base
  end

config :cuckoding_shell_spike, CuckodingShellSpike.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: port],
  url: [host: "127.0.0.1", port: port, scheme: "http"],
  check_origin: ["http://127.0.0.1:#{port}"],
  secret_key_base: secret_key_base
