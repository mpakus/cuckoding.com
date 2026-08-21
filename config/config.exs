# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :agent_desk,
  ecto_repos: [AgentDesk.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true],
  features: [
    xerj: false,
    shared_workspace_mode: false,
    raw_provider_events: false,
    generic_pty: false
  ],
  a2a: [
    max_delegation_depth: 3,
    max_delegation_fan_out: 4,
    max_open_proposals_per_agent: 4,
    idempotency_ttl_hours: 24,
    default_message_ttl_seconds: 86_400
  ],
  providers: [
    use_fixtures: false,
    executables: %{}
  ]

config :agent_desk, AgentDesk.Repo,
  journal_mode: :wal,
  busy_timeout: 5000,
  cache_size: -64_000,
  temp_store: :memory,
  foreign_keys: :on,
  synchronous: :normal,
  pool_size: 5

config :ex_tauri,
  version: "2.5.1",
  app_name: "AgentDesk",
  host: "localhost",
  port: 4000

# Configures the endpoint
config :agent_desk, AgentDeskWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AgentDeskWeb.ErrorHTML, json: AgentDeskWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AgentDesk.PubSub,
  live_view: [signing_salt: "uA1wZv6i"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  agent_desk: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  agent_desk: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :project_id, :agent_id, :correlation_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
