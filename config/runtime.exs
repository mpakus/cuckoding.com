import Config

# Test runs never use the user's data directory, even if BOSS_DATA_DIR is set.
data_dir =
  if config_env() == :test do
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
    directory = Path.join(System.tmp_dir!(), "boss-test-#{suffix}")
    File.mkdir!(directory)
    directory
  else
    Path.expand(System.get_env("BOSS_DATA_DIR", "~/.boss"))
  end

port = if config_env() == :test, do: 4002, else: String.to_integer(System.get_env("PORT", "4000"))
unless port in 1..65_535, do: raise("PORT must be between 1 and 65535")

config :boss, :data_dir, data_dir
config :boss, Boss.Repo, database: Path.join(data_dir, "boss.db")

config :boss, BossWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: port],
  url: [scheme: "http", host: "127.0.0.1", port: port],
  check_origin: ["http://127.0.0.1:#{port}", "http://localhost:#{port}"],
  secret_key_base: Base.encode64(:crypto.strong_rand_bytes(64))

if System.get_env("PHX_SERVER") == "true" do
  config :boss, BossWeb.Endpoint, server: true
end

if config_env() == :dev do
  config :boss, BossWeb.Endpoint,
    live_reload: [
      patterns: [
        ~r"priv/static/.*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        ~r"lib/boss_web/.*\.(ex|heex)$"E
      ]
    ]
end
