# R050a — Battle preparation preview

Claimed from clean local main `7b6dc07` on `feature/r050a-battle-preview`.
Acceptance: [task](../tasks/R050a-battle-preview.md).

Read the core product/architecture/data/flow/security/execution contracts and
reference-coding guidance. Apply Ponytail full 4.13.0 (MIT), Elixir/LiveView,
workflow-and-kanban, security-review and quality-gates. Local-runner/menubar-shell
rules apply to packaged QA only. No new process/runner or architectural boundary.

Reuse Apache-2.0 source at `7b6dc07`: `lib/cuckoding/team.ex:24` catalog/bindings,
`lib/cuckoding/team_assignments.ex:6` scoped revision, `lib/cuckoding/tabulae.ex:43`
current draft/revision join, `lib/cuckoding/specifications.ex:222` current acceptance
and `:244` verified artifact read, `lib/cuckoding/arena_git.ex:91` latest observation.
No peer code/dependency is needed. Historical memory informs the single-Start
contract only; current source establishes delivered capability.

Read-only observation adds no persisted transition and therefore no synthetic
audit event. Existing saves/inspection commands retain their own audit records.
The preview is explicitly not Start authority or a reserved/frozen battle.

RTK proxy exceptions: exact source reads and local editing/evidence scripts;
packaging requires unchanged command semantics. No stored command is wrapped.

## Implementation

Added a session-protected Battle preview link/page per Tabula, with four native
disclosures: Git baseline, assigned team, saved tasks and project checks. The
read model uses the scoped assigned team, current draft-revision command,
existing acceptance/prerequisite validation and private Markdown hash reader.
Manual ToDo placement is not acceptance. Exact saved argv/timeouts remain data.
Git status is based on the latest completed validated receipt, with a five-minute
freshness window; it does not inspect Git or claim live cleanliness/identity.

The preview marks any saved update or one minute of age as stale. Refresh reads
again and preserves disclosures/focus. Its timer generation rejects old expiry
messages after refresh. Every event/update uses the existing session guard.
No database or native source changes, migrations, dependencies or agent calls.
No accepted spec, role binding, check declaration or preview authorizes execution.

## Verification

- `rtk mix format`: passed. Initial `rtk mix compile --warnings-as-errors` caught
  a nil Git clause with the wrong arity and an unsupported interpolated fragment
  in a verified route; fixed both before focused tests. Subsequent compiler gates
  passed through `mix quality` and production packaging.
- `rtk mix test test/cuckoding/battle_preview_test.exs test/cuckoding_web/battle_preview_live_test.exs`:
  6 passed. Covers scope refusal, no command/event effects, manual ToDo, retained
  artifact tampering, prerequisite drift, exact checks, Git receipt validation/
  pending/expiry/future-clock refusal, explicit team adoption, catalog/model drift,
  escaped task text, refresh, timer generations, reconnect and expired sessions.
- `rtk mix quality`: final 156 tests passed; formatter, warnings-as-errors
  compiler, strict Credo, Sobelow and dependency audit passed. Repeated after the
  two browser-discovered UI fixes below. Known Sobelow Elixir 1.20 generated-lockfile
  quoted-key warnings remain; no new exclusions or vulnerabilities.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r050a-target bin/dev.build`:
  passed, including rebuilds after UI fixes. Existing Tailwind ad-hoc re-signing
  and OpenSSL relocation/re-sign diagnostics only. Native code is unchanged;
  no repeated Rust lint/unit gates were needed.
- `rtk proxy python3 /private/tmp/cuckoding-r050a-proof-oshse0xm/verify-package.py`:
  fresh and copied-prior native smoke passed, including bootstrap/session/origin/
  replay checks, heartbeat and graceful Quit/listener cleanup. Eight migrations,
  integrity/FKs, all prior commands/teams/drafts/adoptions/four check revisions and
  two specification files preserved. Source stopped R040j DB unchanged, SHA-256
  `8e1190a26615d5dd54a6c420d514ab94e2921e01242fae25ff8375e28a1720c6`.
- `rtk proxy python3 /private/tmp/cuckoding-r050a-proof-oshse0xm/final-smoke.py`:
  final rebuilt artifact smoke and graceful Quit passed. The first draft of this
  QA script omitted the smoke-only `CCODING_RELEASE_DIR`; it exited 1 before
  service startup. Added the required variable and used new isolated roots;
  this was a harness error, not passing product evidence.

## Packaged UI

QA root `/private/tmp/cuckoding-r050a-proof-oshse0xm`; copied synthetic data with
no provider credentials. `start-browser.py` launches only the selected native
bundle against `prior/`; `connect-browser.py` validates its child/listener and
creates a test-only one-use handoff. Both invoked with `rtk proxy python3`.

CUA followed Arenas → Open Tabulae → Linked release plan → Battle preview. The
page showed the assigned team, two saved tasks (one unaccepted prerequisite and
one current verified specification), and check revision 4 with exact commands
and 180/300-second timeouts. No process/check/provider was invoked by the page.
Keyboard Enter opens native disclosures. Refresh retains open Tasks/Checks.

Browser verification caught a setup link pointing at Home instead of Agents;
fixed it to `/settings` and added a regression. It also caught Refresh losing
focus because `phx-disable-with` disabled its button; removed that unnecessary
behavior, gave the control a stable ID and verified the final focused element
remains `refresh-preview` after Enter. The corrected Agents action opened the
actual setup screen. Final desktop 1280×900 and narrow 390×844 screenshots were
visually inspected; narrow document width equals 390px, including wrapped hashes
and literal argument arrays. No CSS or browser-hook changes were needed.

`rtk proxy python3 /private/tmp/cuckoding-r050a-proof-oshse0xm/verify-restart.py`:
after controlled restart, all command/check/draft/team rows and both Markdown
hashes were identical; startup events only appended. No pending work or replay.
Restarted UI re-derived the same saved evidence. This checks persisted preparation,
not nonexistent battle recovery. Screenshots: `/private/tmp/cuckoding-r050a-desktop.jpg`
and `/private/tmp/cuckoding-r050a-mobile.jpg`.

Final bundle: `/private/tmp/cuckoding-r050a-target/release/bundle/macos/Cuckoding.app`.
Native SHA-256 `8ad7026b61dbf8c1b8db823b306c9aeb22a168701937a257ea10ac98a5cac04e`;
BattlePreview BEAM `52f7c93a15740d87e44a34e917ae216c8351eca3c17c423bc753ec0f547bf37b`;
BattlePreviewLive BEAM `7c9e91fae24a350f4bd8243300d0dc87daa8bc467fc009b6c1822a097787cdf2`.
These identify the tested implementation, not a public release.

No migration, task process, scheduler, port allocator or sleep behavior changed;
those gates, real-provider acceptance, clean-machine signing and battle execution
remain open. Next execution work is the recorded Start authority and owned worktree
runner, followed by actual checks/agent stages/review. No push or site deployment.

Final running bundle showed the one-minute stale notice while preserving keyboard
focus and open disclosures. Temporary browser tabs were closed and the viewport
override reset. `rtk proxy python3 /private/tmp/cuckoding-r050a-proof-oshse0xm/stop.py`
verified each owned executable/parent identity, sent BEAM SIGTERM, observed shell
heartbeat exit and confirmed listener cleanup: `46155/46156/56842`,
`47149/47150/57084`, `47927/47928/57275` (shell/BEAM/port). All are stopped.
These controlled service exits are distinct from the graceful shell Quit tested
by packaged smoke. No QA app remains running.

A final `rtk proxy python3` read-only comparison checked every prior command,
team, Arena, board, draft and check row against the stopped source, plus unchanged
source DB hash, Arena document/canary bytes and absent `.git`. The preview created
no commands or workflow mutations. `rtk proxy python3
/private/tmp/cuckoding-r050a-proof-oshse0xm/check-docs.py` validated 102 local
Markdown link targets; `rtk git diff --check` passed. README, AGENTS and affected
docs describe the delivered read-only boundary and remaining execution work.

Local integration: pending.
