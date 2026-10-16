# R080e — Disconnect and reset

2026-10-16. Codex; Ponytail full 5.2.0 (MIT), agent-adapter, LiveView, security
and quality-gates instructions. Clean start on main `3365218`, ahead 39.

## Acceptance and diagnosis

Fix Cursor disconnect and provide a complete local workspace reset script. No
new provider calls, credential reads, model usage or reset of real user data.
Read-only saved SQLite inspection confirms two successful Cursor logout receipts;
its current projection is `checked / not_connected`. The roster only recognizes
`status: disconnected` (local-only fallback), so verified logout continues to show
an enabled Disconnect button. Preserve the raw normalized logout observation,
scoped role unassignment and all uncertain/failed states.

Reset must include database registrations, agents, roles, Arenas, boards, tasks,
history, app-owned profiles and artifacts. Keep the storage root's shell lock in
place while moving its other entries into one private sibling archive; this
preserves the running-app exclusion. Require recognized private storage, stopped/
settled work, valid SQLite and explicit confirmation. Archive, never follow,
profile symlinks; never traverse/delete external project folders or provider homes.
Remove the old marker first so partial reset fails closed. Fresh storage boots
through the existing migrations/default Team seed. Do not execute the reset on
the saved user workspace in this request.

`rtk proxy` is used for exact protocol/source/SQLite, Python checks, pinned build
and test output.

## Implementation

Foundation derives Disconnected only from validated native checked/not_connected
logout; its event keeps the original normalized observation. Agents recognizes
pre-fix current projections through the exact completed logout command, kind and
connection ID, never from a missing process or arbitrary signed-out inspection.
Roster display/controls use this read-only predicate; old receipts are unchanged.
The wizard returns signed-out saved connections to authorization, preserving
historical model selections and guarded login. No provider/grant/schema changes.

Reset holds the original root lock, validates settled work and SQLite, archives
everything except that lock into a private sibling's `workspace/`, and fsyncs
dated intent/archival events in `reset.jsonl`. Fresh marker/lock-only storage
initializes normally on next launch. External profiles, project folders and
project Git registrations are not traversed or changed. No purge/force option.

## Verification

- `rtk proxy env PATH=<pinned> mix test test/cuckoding/agents_test.exs
  test/cuckoding_web/agents_live_test.exs test/cuckoding/authorization_test.exs`:
  22 passed. The initial regression exposed the saved-model wizard landing on
  Save after sign-out; its initial-step selection now preserves authorization
  as the next action. Tests distinguish cancelled/uncertain results and retain
  raw checked/not_connected evidence with exact historical binding checks.
- `rtk proxy env PATH=<pinned> mix quality`: 373 tests passed, format/compile,
  Credo, Sobelow and dependency audit passed. The first run flagged projection
  complexity; a small pattern-matched logout projection resolved it. Existing
  Sobelow quoted-keyword warnings remain; dependency scan found no vulnerabilities.
- `rtk proxy python3 test/reset_agents_test.py`: eight tests passed, including
  complete private archive/receipt, lock reuse, cancellation/EOF, running and
  unresolved work refusal, canonical/marker/project checks, corrupt/linked DB and
  sidecars, FK damage, env-selected paths with spaces and injected partial move.
  Direct execution avoids Python's standard-library `test` package name collision
  encountered with `python3 -m unittest test/reset_agents_test.py`.
- `rtk proxy python3 bin/reset-agents --help`: passed. Executable bit set.
- `rtk proxy env PATH=<pinned> mix format --check-formatted`,
  `rtk proxy git diff --check` and affected Markdown local references passed.
- `rtk proxy env PATH=<pinned> bin/dev.build`: passed. As in R080d, the first
  generated-release cleanup saw a newly appeared `.DS_Store`; inspection found
  only that metadata file, and the unchanged build passed on retry.
- Packaged native `--smoke-test` before and after reset of a new disposable root
  passed launch, bootstrap/cookie, handoff replay/origin refusal, heartbeat,
  graceful quit and listener cleanup. Root:
  `/private/tmp/cuckoding-reset-proof-7pxs31pt`; archive:
  `/private/tmp/cuckoding-reset-proof-7pxs31pt-reset-7osgk2i5`.
  Seeded one synthetic connection/profile in that fixture only. Reset and second
  native launch yielded eleven migrations, four blank required roles, zero
  agents/Arenas/boards/tasks/commands/battles and clean SQLite integrity/FKs.
  The archived original DB/profile remained intact. No actual credentials used.

Pinned PATH:
`/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
No Rust/JS changes; separate Rust/Node suites were not repeated. No physical
crash/sleep, fresh provider logout/login or inference acceptance was claimed.

## Running saved workspace

Verified no active commands/battles, DB integrity/FKs, exact backend executable/
parent/start/cwd/listener. Online backup retained at
`.ccoding/r080e-validation/before-rebuild.sqlite3` (0600, ignored).
Used the documented unavailable-tray fallback: audit-token-bound normal SIGTERM
to backend 90217; backend and shell 90215 exited and port 56507 closed. No
escalation or unrelated process signal; no `shell.quit_requested` tray event.

Reopened the unchanged saved `Open Cuckoding Test.command`, keeping
`/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`. Native/backend PIDs
94925/94927, listener `127.0.0.1:57615`. All 14 non-session state tables and 278
preexisting events match the backup; integrity/FKs passed. All 73 assembled/
bundled ebin artifacts match. Identities are dated observations.

Native Chrome read-only verification: existing Cursor card now says Disconnected
with disabled Disconnect; Edit opens step 2 with Sign in with Cursor, no refresh
and disabled Next. No provider button clicked and no extra logout, settings
save, model usage or real reset performed. The user's current data is preserved.

## Integration

Pending local commit/merge. No push/publication; the reset helper is ready for
the user to run with explicit target/confirmation after quitting the app.
