import Config

config :cuckoding, CuckodingWeb.Endpoint,
  server: true,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("CCODING_DEV_PORT", "4000"))],
  code_reloader: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:cuckoding, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:cuckoding, ~w(--watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/cuckoding_web/.*(ex|heex)$"
    ]
  ]

config :phoenix_live_view, debug_heex_annotations: true, debug_attributes: true
