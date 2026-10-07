import Config

if config_env() != :test do
  root = System.fetch_env!("CCODING_DATA_DIR")
  Cuckoding.Storage.prepare!(root)
  boot = Cuckoding.Storage.consume_bootstrap!(root, System.fetch_env!("CCODING_BOOTSTRAP_FILE"))
  config :cuckoding, :bootstrap_hash, :crypto.hash(:sha256, boot["bootstrap"])
  config :cuckoding, :data_dir, root
  config :cuckoding, :native_helper, System.fetch_env!("CCODING_NATIVE_HELPER")
  config :cuckoding, :discovery_home, System.get_env("CCODING_DISCOVERY_HOME")
  config :cuckoding, Cuckoding.Repo, database: Path.join(root, "foundation.db")
  config :cuckoding, CuckodingWeb.Endpoint, secret_key_base: boot["signing"]
end
