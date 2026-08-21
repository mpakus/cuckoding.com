# Release checklist

Use this before a signed macOS build.

## Packaging status (Apple Silicon, OTP 28)

Recorded 2026-08-21 on Elixir 1.19 / OTP 28:

| Step | Result |
| --- | --- |
| `MIX_ENV=prod mix compile --warnings-as-errors` | Pass (compile first so colocated hooks exist) |
| `MIX_ENV=prod mix assets.deploy` | Pass after compile |
| `MIX_ENV=prod mix release desktop --overwrite` | Pass — `_build/prod/rel/desktop` |
| `mix ex_tauri.build --ci --bundles app` | Fail — ExTauri copies `burrito_out/desktop_aarch64-apple-darwin`, which Burrito does not emit on this OTP |

ExTauri 0.2.0 warns that it targets OTP 27. Until Burrito ships an OTP 28 ERTS (or AgentDesk pins OTP 27 for packaging), ship via `mix phx.server` / `mix ex_tauri.dev`. Do not treat `_build/prod/rel/desktop` as a signed desktop installer; it is a Mix release only.

Asset deploy order:

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

Until that pipeline runs on a clean Mac, distribution stays developer `mix ex_tauri.dev`.

## Linux and Windows

`src-tauri/tauri.conf.json` already sets `bundle.targets` to `all`. Linux (AppImage/deb) and Windows (msi/nsis) follow the same ExTauri/Burrito path as macOS and remain unverified on OTP 28.

Until a platform ERTS exists:

- develop with `mix phx.server` bound to loopback;
- optionally `mix ex_tauri.dev` on that OS;
- do not ship unsigned installers from CI.

When OTP 28 Burrito artifacts exist, add per-OS smoke tests: install, loopback bind, SQLite under the platform `data_root`, and updater HTTPS.
