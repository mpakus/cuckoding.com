# R080f — Guided flow

2026-10-16. Owner: Codex. Clean main `190f36a`, 41 ahead of origin/main.
Ponytail full 5.2.0 (MIT), project LiveView/workflow/security/quality instructions.

## Requested skills

Installed all 25 `addyosmani/agent-skills` skills using the system skill-installer
at `aeac41d4d005999432bb7312f7ff06383a91d59d`, MIT. Verified installed SKILL.md
bytes against pinned upstream, installed all seven original shared references at
their expected relative paths, and retained source/hash/license manifest under
`~/.codex/skills/.sources/addyosmani-agent-skills/`. No existing skill overwritten.
System Python's CA setup failed; Homebrew Python completed installation with TLS
verification intact. No certificate bypass or new app dependency.

Applied frontend-ui-engineering (hierarchy, context, keyboard/responsive states),
code-simplification (understand gates, remove duplicated consent state), and
incremental-implementation (verified slices). Reference: pinned
`skills/frontend-ui-engineering/SKILL.md:120`,
`skills/code-simplification/SKILL.md:100`, and
`skills/incremental-implementation/SKILL.md:89`. Examples are adapted to the
existing LiveView/HEEx/SQLite stack; generic React/migration guidance cannot
override project rules. Native pack discovery applies next turn; direct reads
apply its guidance now. No managed provider profile or permission is changed.

## Design and acceptance

Use existing Agent wizard, four-role Team editor and Arena board as references.
Keep black/green tokens, one/two regions, existing sidebar and native dialog.
Screen jobs: Team makes explicit role/model choices; Board team previews the
exact future team; Arena exposes Create tasks/Start. Keep the exact board context
through repairs, return directly to its review, and confirm adoption with one
clearly scoped submit instead of a checkbox plus submit. Do not silently adopt,
choose accounts/models, send documents, invoke providers or start battles.
Do not call identical role definitions a changed team solely because IDs differ.
History, source snapshots, domain audits, planning locks and revision/session
guards remain authoritative. No schema, grant or scheduler changes.

`rtk proxy` preserves exact installer/TLS/source/SQLite and verification output.

## Delivered

Team repair links carry validated Arena/Tabula IDs, not an arbitrary return URL.
Team preserves that context and dirty form through PubSub, then offers a direct
Review team link after Save. It opens the exact board dialog; saving alone never
adopts. The one Use saved team submit binds its server-owned component key and
both displayed revisions, with key rotation on scope/default changes. Domain
session, confirmation, idempotency and active-planning gates remain unchanged.
Adoption closes the dialog and restores focus. Same-definition revisions no longer
cause misleading adoption notices. Compact role/model rows and optional instruction
disclosures keep the comparison short without hiding audit/history.

## Verification

Pinned toolchain PATH for Mix/build commands:
`/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.

- `rtk proxy env PATH=<above> mix test test/cuckoding_web/team_live_test.exs test/cuckoding_web/team_adoption_live_test.exs test/cuckoding_web/battle_live_test.exs`:
  40 passed after the flow change. New checks failed before implementation. Existing
  checkbox tests now exercise the explicit submit, stale keys/current/default
  revisions and expired sessions; domain confirmation tests remain intact.
- `rtk proxy env PATH=<above> mix quality`: final run 376 tests passed,
  format/compile/Credo passed, Sobelow found no vulnerabilities. Its existing
  quoted-keyword lockfile warnings remain. An initial Credo complexity finding
  was fixed by naming the exact-form predicate; final gate has no findings.
- `rtk proxy node --test test/dialog_test.mjs test/agent_login_test.mjs`: 4 passed.
  The dialog test covers focus restoration from a deep link; login behavior stays
  unchanged.
- `rtk proxy env PATH=<above> mix assets.build`: passed. Source CSS watcher had
  not published the new rules; explicit build and served-asset inspection verified
  them before browser checks. No watcher behavior was changed.
- Native Chrome walkthrough on isolated `.ccoding/ui-dev/` data at port 54052:
  Arena repair → contextual Team → edit test role → Save → exact board dialog →
  one Use saved team. Dirty inputs/context survived; assignments changed only on
  the submit; dialog closed and focus returned to Board team. No provider started.
  Inspected wrapping/scrolling at 320/768 and layout at 1024/1440 CSS-pixel widths.
  The 320-pixel dialog scrolls to its single confirmation. Desktop full-page proof
  retained privately at `.ccoding/r080f-validation/team-desktop.png`.
  These are browser checks on synthetic development data, not timed real-account
  onboarding or screen-reader/device acceptance.
- Temporary source preview/tab stopped/closed; port 54052 closed and source
  launcher exited 130. Normal browser layout restored; unrelated tabs untouched.
- `rtk proxy env PATH=<above> bin/dev.build`: passed first attempt; unchanged
  locked dependencies. All 73 assembled/bundled app ebin files match byte-for-byte.
- `rtk proxy bin/smoke`: passed bundled bootstrap/session, handoff replay/origin,
  heartbeat, graceful quit and listener cleanup. Isolated data retained at
  `/private/tmp/ccoding-smoke.HHRJ2f`.
- `rtk git diff --check`: passed. Local Markdown target validation: 171 targets
  exist across changed docs/task/worklog. All 25 installed SKILL.md hashes match
  the pinned manifest; seven original shared reference files exist.

## Preserved workspace and running artifact

The previous tray remains unavailable per the user's report. Verified old native
94925/backend 94927 executable/parent/start identity, data-root cwd and loopback
57615 listener. No active commands/battles; SQLite integrity/FKs passed. Retained
0600 online backup at `.ccoding/r080f-validation/before-rebuild.sqlite3`. Used
macOS audit-token-bound normal SIGTERM on the idle backend; verified native
heartbeat exit and listener closure, without escalation. This fallback records
no `shell.quit_requested` event.

Launched the preserved `Open Cuckoding Test.command`, keeping
`/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`. New native 29045/backend 29047,
2026-10-16 14:12:43 local start, listener `127.0.0.1:56513`. All 14 durable tables
and 281 prior events match backup; integrity/FKs pass. Two Arenas, two tasks and
two UUID connections retained, with legacy Codex still separate. Current teams
remain intentionally unassigned after the earlier user-requested disconnections.
No reconnect, provider inference, role substitution or battle was run.

Running bundle serves the compact roster CSS. Native browser verified preserved
Ura Mawashi/Beta cards and exact context in its repair link. Source/build/browser
proof does not establish real-provider battle acceptance, clean-machine install,
physical recovery or timed ten-minute setup.

## Integration

Verified slice ready to commit and merge into local main; no push/deployment.
