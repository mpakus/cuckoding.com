# BOSS

Local AI agent orchestration, rebuilt from [BOSS_PLAN.md](BOSS_PLAN.md).

The current increment bootstraps Phoenix LiveView, Tailwind and Ecto SQLite.
Projects, specifications and agent execution are not implemented yet.

## Development

Use Elixir 1.20.3 compiled for OTP 28 and an OTP 28 runtime. `.tool-versions`
pins Elixir; Erlang/OTP is provided by your local installation.

```sh
rtk proxy mix setup
rtk proxy mix phx.server
rtk proxy mix test
rtk proxy mix compile --warnings-as-errors
rtk proxy mix format --check-formatted
```

The access/data-directory controls are being implemented in the next commit.
