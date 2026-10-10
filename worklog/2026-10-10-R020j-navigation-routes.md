# R020j · Correct Agents and Settings routes

Claimed on clean main e21d964; branch fix/R020j-navigation-routes.
Acceptance: tasks/R020j-navigation-routes.md.
Scope: router and live-action names, sidebar/setup/Team/Battle links, tray menu and
its bounded handoff allowlist, session redirect, LiveView tests, packaged smoke, docs.
No database/provider/profile changes. Old wizard and About bookmarks redirect to
the matching canonical page; the old roster URL now means Settings as requested.
Ponytail full 5.1.0 (MIT), LiveView, quality-gates and local-runner/security review
for native handoff/restart apply. RTK prefixes shell commands; `rtk proxy` keeps
exact source/script/build output where filtering changes semantics. No new dependencies.

Implementation: `/agents` owns the roster and `/agents/:id` owns each wizard.
`/settings` now renders workspace settings with the correct active sidebar item.
All setup/Team/Battle links use `/agents`. The tray has an explicit Agents shortcut;
Settings and About open `/settings`. Legacy `/about` and `/settings/:id` are bounded
local redirects, with protected destinations. No navigation audit event is needed
because these requests change no durable product state.

Validation:
- `rtk mix quality`: 179 tests passed; format/compile, Credo, Sobelow and audit passed.
  Existing Sobelow quoted-keyword warnings from Mix.lock remain; no vulnerabilities.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: passed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: 48 passed.
- `rtk proxy bin/dev.build`: passed. Normal dylib relocation/re-sign warnings only.
- `rtk proxy bin/smoke`: passed; data retained at `/private/tmp/ccoding-smoke.XXlTbA`.
  The packaged check now verifies unauthenticated rejection on both routes, the
  `/agents` handoff Location, roster content and workspace-settings content, plus
  existing single-use, origin, heartbeat, graceful shutdown and listener cleanup.
- LiveView regressions assert both page titles/navigation targets/active states,
  wizard navigation, legacy redirects and allowed/rejected handoff destinations.
- `rtk git diff --check`: passed. `rtk proxy python3` validated 112 changed-document
  relative Markdown link targets. Historical worklogs keep their original URLs.

No provider prompts or new grants; migration/sleep/provider acceptance tests were
not repeated for a route-only change. Browser session/origin protections are unchanged.

Running artifact: `/private/tmp/cuckoding-r020j-proof-2a50xw5o/Cuckoding.app`. Native SHA-256 `d159b361d937a244dd95d94b297f1b74fc6e55489022ee2676fa965429ea58b7`.
Shell PID 38588 (Sat Oct 10 13:30:42 2026), BEAM PID 38596
(Sat Oct 10 13:30:42 2026), loopback port 56235. Data stays at `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`.
No pending/running/cancelling setup operation existed before restart. The previous
proof's `stop.py` verified executable/parent/start identity, sent graceful SIGTERM
to the owned service and confirmed shell/listener cleanup. The new proof's
`launch.py` used the native handshake with the same data. Existing test launchers
were updated to this artifact.

Native Chrome verification: clicked Agents in the sidebar, observed URL `/agents`,
Agents heading, Add/Edit links under `/agents`, and existing signed-in Codex with
its saved model selection. Clicked Settings and observed `/settings`, Settings
heading and Local by design content. No appearance changes or screenshot needed.
Packaged smoke checks plus these browser clicks verify the requested navigation.

Local integration: verified R020j is committed and fast-forwarded into local main;
the task branch is deleted. No remote push or deployment.
