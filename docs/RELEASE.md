# Release checklist

Use this before a signed macOS build.

## Local `.app` (Apple Silicon, OTP 28)

Burrito has no OTP 28 ERTS, so `mix ex_tauri.build` cannot wrap a single BEAM binary. For local use, `mix cuckoding.app` copies the Mix release (this machine's ERTS) into Tauri resources and starts it with a sidecar shim.

```bash
mix cuckoding.app
```

`mix desktop.app` is an alias. Output: `src-tauri/target/release/bundle/macos/Cuckoding.app`

Unsigned, this-machine OTP, loopback only. Not a notarized installer.

Quit the running Cuckoding `.app` and any leftover `beam.smp` before rebuild, or the copy into the bundle fails.

Asset deploy order if you assemble the Mix release by hand:

```bash
SECRET_KEY_BASE=$(mix phx.gen.secret) MIX_ENV=prod mix compile --warnings-as-errors
SECRET_KEY_BASE=$(mix phx.gen.secret) MIX_ENV=prod mix assets.deploy
SECRET_KEY_BASE=$(mix phx.gen.secret) MIX_ENV=prod mix release desktop --overwrite
```

`phoenix-colocated/agent_desk` fails if `assets.deploy` runs before the prod compile.

## Security

- [ ] HTTP and XERJ bind loopback only (`AgentDesk.Security.Loopback.assert!/0`).
- [ ] Diagnostic export fixtures contain no raw secrets (`mix test` hardening suite).
- [ ] Capability tokens expire, rotate, and revoke on session terminate.
- [ ] Permission profiles: `default` (all hub tools) and `observer` / `restricted` (read/search only).
- [ ] No `String.to_atom/1` on user input.
- [ ] Sobelow, Credo, Dialyzer, and `mix test` are green.

## Recovery

- [ ] Startup reconciliation expires leases, delegations, and tokens; interrupts orphan sessions.
- [ ] Provider and XERJ crash loops trip `AgentDesk.Circuit` after five failures.
- [ ] Dirty worktrees survive runtime stop and app quit.
- [ ] SQLite snapshot documented in `OPERATIONS.md`.

## Accessibility (MVP baseline)

- [ ] Tabs, composer, approvals, and search controls are reachable by keyboard.
- [ ] Icon-only buttons have `aria-label`.
- [ ] Destructive actions require an extra confirm click.

## macOS signing and updates

Not executed in CI until Apple Developer certificates are available.

1. Build the Phoenix release / Burrito binary once OTP compatibility is confirmed.
2. `mix ex_tauri.build` with `src-tauri` bundle identifiers already set (`com.agentdesk.app`).
3. Sign with `codesign --deep --force --options runtime`.
4. Notarize with `xcrun notarytool`.
5. Staple and ship through a Sparkle- or Tauri-updater channel bound to HTTPS.

Until Apple certificates exist, local distribution is `mix cuckoding.app` (unsigned `.app`) or `mix ex_tauri.dev`.

## Linux and Windows

`src-tauri/tauri.conf.json` local builds use `bundle.targets: ["app"]`. Linux and Windows installers follow ExTauri/Burrito and remain unverified on OTP 28.

Until a platform ERTS exists:

- develop with `mix phx.server` bound to loopback;
- optionally `mix ex_tauri.dev` on that OS;
- do not ship unsigned installers from CI.

When OTP 28 Burrito artifacts exist, add per-OS smoke tests: install, loopback bind, SQLite under the platform `data_root`, and updater HTTPS.
