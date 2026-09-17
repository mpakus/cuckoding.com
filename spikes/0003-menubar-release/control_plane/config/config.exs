import Config

config :cuckoding_shell_spike, CuckodingShellSpike.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  live_view: [signing_salt: "shell-spike-live"],
  pubsub_server: CuckodingShellSpike.PubSub,
  server: true

config :phoenix, :json_library, Jason
config :logger, level: :warning

import_config "#{config_env()}.exs"
