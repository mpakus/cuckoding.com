# Data model

Target schema, to be implemented incrementally. Use Ecto and SQLite with WAL,
foreign keys, a busy timeout and short write transactions. Persist workflow
truth here; files store human-readable content and processes do the work.

R010 currently creates four tables: singleton `workspace` (setup projection and
revision), `commands` (UUID key, expected revision, status, three-attempt limit
and ten-second claim), append-only `events`, and `browser_tokens` (SHA-256
digests, purpose and expiry). Events use an ordered integer sequence; command
IDs are UUIDs. SQLite triggers reject event updates/deletes. Startup refuses
unknown migration versions. Two pooled connections allow the Ecto migration
lock and migration query to coexist; the busy timeout is five seconds.

R020a adds `workspace.codex` for the last public version observation and
`commands.payload` for the consented executable metadata (path, device/inode,
size and change/modify times). `probe_codex` shares command keys/revisions and
the event stream. Cancellation is durable; late results are refused. Expired
running probes become `failed/interrupted` and require a fresh command, while
metadata discovery retains its bounded automatic retry. A completed check can
report unsupported/failed readiness; it never changes account authorization.
The observed PID/spawn time is evidence, not authority to signal that PID after
restart. Only the native helper's unreaped child handle authorizes group cleanup.

R020b adds `workspace.connection`, separate from version readiness. It records
normalized account observation/time, executable identity, catalog entries/source/
fetched time and the last inspection outcome. No email, plan details, raw frame,
credential or auth URL is copied into Cuckoding tables/events. A successful
catalog replaces the snapshot; a failed refresh keeps the last entries as stale.
Freshness is derived from the stored timestamp (24 hours), never an in-memory
clock alone. Signed-out/unsupported account observations clear unusable entries;
a changed executable identity clears the connection projection. R020c login/logout
invalidate account-dependent observations when intent is enqueued, before launch.

`inspect_codex` uses the same idempotent command ledger, a 20-second claim and
bounded helper execution. Expired inspections are interrupted, never replayed.
Cancellation prevents late completion. Events contain outcome/count/timing only;
full validated model metadata belongs in the connection projection. The single
Codex profile is `agents/codex` beneath the private rebuild root; Codex owns its
contents. Named/multiple profiles are not enabled.

R020c reuses these tables without a migration. `login_codex` / `logout_codex` use
630-/20-second claims and exclude other setup commands while pending, running or
cancelling. The helper has a ten-minute total login limit and ten-second RPC
limits. `login.awaiting_browser` stores public progress only; the URL stays in
expiring memory. Running cancellation becomes `cancelling/awaiting_cleanup` until
the helper exits or cleanup times out visibly; late results cannot restore an old
catalog or report a cancelled
operation as successful. Expired claims become interrupted, never replayed.
A later explicit inspection reconciles uncertain provider state.

R020d also needs no migration. `check_codex_model` snapshots the executable,
connection command/fetch time, catalog ID, model, effort and versioned scratch
grant before launch. A 140-second claim covers the 120-second native operation
and cleanup. The command excludes other setup operations and cannot replay after
interruption. `workspace.connection.model_check` holds a closed public receipt:
status, requested/runtime model, effort, thread/turn UUIDs, grant and measured
timing. Successful receipts must match the saved intent and current connection.
Starting another check or refreshing/changing the connection clears its current
projection while append-only `model_check.*` events retain historical evidence.
Cancellation holds admission until cleanup and cannot record late success.

R030a adds append-only `team_revisions` (integer revision ID, unique nullable
command ID, versioned JSON definition, UTC creation time). Migration seeds the
four unassigned responsibilities as revision 1; custom roles use stable UUIDs.
Definitions store ordered names/instructions, agent, catalog ID and resolved model
identifier, with `execution: disabled`. Role text never becomes a grant. Names are
unique after trim/case folding, at most 60 characters; instructions at most 2,000;
teams contain 4–12 roles. SQLite triggers prohibit revision updates/deletes.

`save_team` commits a completed/rejected command, revision when accepted and
`team.saved`/`team.rejected` event in one short transaction before broadcast.
Its expected revision is the **team** revision, not `workspace.revision`; saving
cannot invalidate provider work. Matching command keys return the original result,
stale editors cannot overwrite current state, and removing saved custom roles
requires explicit confirmation. Events contain counts/revision/removed IDs or a
closed reason, not instruction text. The UI exposes the latest five revisions;
older history remains in SQLite. Existing bindings retain the resolved model
through disconnect or catalog drift; new bindings require verified fresh metadata.
Arena/Tabula overrides, schedules and executable grants are not implemented.

R040a adds `arenas`: UUID, registration/selection command references, name,
canonical path, device/inode identity, observed Git-entry presence, immutable
`team_revision_id` and UTC creation time. Unique indexes cover path, device/inode,
registration and selection command IDs. The team reference freezes the version
displayed at selection, even if the default changes before registration.

`choose_arena_folder` snapshots the team ID, serializes with setup operations and
uses a 135-second claim around the two-minute dialog. Its bounded validated
folder projection and measured duration live in command payload; events retain
closed status/timing only. Cancellation waits for helper exit; expired running
claims become interrupted without replay. `register_arena` records confirmed
intent, Arena and event atomically after identity/duplicate checks. Neither
command changes `workspace.revision`. Names are 1–80 characters and paths at most
4,096 bytes. Directory replacement requires reselection; future file execution
must revalidate identity and grants. Registration is not a filesystem lock.

R040b adds immutable `tabulae` (UUID, Arena/team references, creation command,
name, version-1 default columns, `execution: disabled`), `draft_tasks` (UUID,
Tabula, current revision/content/column and timestamps) and append-only
`draft_task_revisions` (task, unique command, revision, full content, timestamp).
Unique task/revision indexes and history/board immutability triggers retain facts;
a draft-stage trigger permits only Specs/ToDo. A future execution schema must
explicitly handle this boundary rather than treating drafts as executable work.

`create_tabula` copies the Arena team, even after global defaults change.
`save_draft` atomically commits the current projection, immutable history and
`draft.saved` event; a failed event rolls back all writes. Matching keys return
the original revision receipt. Scope/stale/stage/readiness rejections are durable.
Events include IDs, revision and old/new columns, never task prose. Neither
command touches setup revisions or enters the dispatcher. Title/description/
criteria limits are 120/8,000/4,000 characters; ToDo needs nonblank description and
criteria. The UI reads the latest five revisions; older history stays in SQLite.
These are manual database drafts, not file-backed accepted specification artifacts.

R040c reuses the six-migration schema. `inspect_arena_git` / `init_arena_git`
snapshot Arena ID, operation, directory identity and (for init) the confirmed
observation command ID. Init requires the latest completed `missing` inspection
to be less than five minutes old. Matching command keys return the same receipt.
They serialize with other setup effects using 25-second claims; cancelled or
interrupted running effects are never replayed. A new inspection reconciles state.
The command payload stores a closed observation (status, measured duration and
validated HEAD hash when committed); `arena_git.*` events contain only IDs,
operation, closed reason/status and duration. Neither setup workspace revisions
nor the Arena's original registration fact changes. This is metadata observation,
not a clean-file inventory or a runnable baseline.

The default native root is `~/Library/Application Support/CCoding Rebuild`,
marked `.ccoding-rebuild-v1`. Unknown nonempty roots and symlinked storage are
refused before migration. `foundation.db` and sidecars are private; old Cuckoding
data is not opened. `CCODING_DATA_DIR` can select an absolute isolated test root.

## Minimal records

| Record | Durable fields / invariant |
| --- | --- |
| Agent connections | Runtime key, executable identity/version, provider-owned profile reference, observed authorization state/time; no tokens |
| Model catalog | Connection/runtime scope, model ID, label, capabilities, source, fetched time, freshness/error status |
| Role definitions and team revisions | Stable role ID, display name, instructions, connection/model, grant, coordinator binding, revision |
| Arenas | Canonical repository path, name, selected base ref, trusted settings revision |
| Tabulae and workflow revisions | Arena, ordered columns/keys, role bindings, entry/exit contracts, limits |
| Specs | Arena/Tabula/task scope, revision, source paths and hashes, Markdown artifact, criteria IDs |
| Tasks and dependencies | Tabula, description, spec/criteria revision, column/status, priority, dependency edges, active attempt reference |
| Battles and items | Arena/Tabula, state/revision, immutable authorization snapshot, task membership, original base and reviewed head |
| Attempts and sessions | Task/stage/role instance, connection, requested/actual model, runtime/grant identity, lifecycle, continuation reference, cumulative counters |
| Reviews/findings | Secutor attempt, spec and candidate hashes, criterion outcomes, check receipts, comments and pass/return/block |
| Environments/processes/leases | Owned worktree/run directory, PID/PGID/start identity, ports, resource owner, token hash, TTL/heartbeat |
| Commands/events | Idempotency key, expected revision, intent/result; stream sequence, public summary, redacted data, UTC time |
| Artifacts | Scope, kind, canonical app-owned path, content hash/size, producing attempt and retention state |
| Approvals | Actor, exact scope/digest, decision/time, consumed status; no reusable blanket authority |
| Integration receipts | Task candidate, old/new battle head, check/review references, pending/completed effect identity |

Keep these as cohesive domain records, not one table per UI widget. Add optional
usage records only when an adapter supplies them; integer token counts, bytes and
money micros with currency/source, never invented measurements. No dedicated
knowledge, plugin marketplace or analytics warehouse schema in the first rebuild.

## Integrity rules

- UUID identifiers, UTC timestamps; monotonic duration measurements with explicit
  sleep gaps. Record boot identity when interpreting clock samples.
- One nonterminal battle per Arena; one live claim per task/stage; one owner per
  worktree, process identity and port. Enforce uniqueness in SQLite, not only UI.
- Dependencies belong to the same Tabula; reject self-links, duplicates and cycles.
  Cross-Tabula execution dependencies are outside the first scope.
- Immutable published workflow, team and policy revisions. Start snapshots the
  goal/spec, membership, bindings, checks, base and finite limits. Later settings
  changes do not rewrite battles or historical attempts.
- Model availability and authorization are live dependencies; snapshot what was
  selected and record the actual observation at launch. Never switch models or
  accounts silently. Catalog refresh failure retains the last good catalog with
  a stale label; it does not overwrite valid login status.
- Every transition and its event commit together. Repeated command keys return
  the stored outcome; stale expected revisions refuse mutations.
- Review binds exact spec/candidate/check hashes. Changing any relevant input
  invalidates that review for completion; historical review rows remain intact.
- Store findings, specifications, attempts and superseded task membership as
  history. A retry does not erase failed work or reset cumulative limits.
- Hash-verify files on read; report missing/changed artifacts. A candidate's text
  report cannot create a successful host-check receipt.
- Approval decisions use a pending-only atomic update, scoped to the exact
  candidate/path set/action. Audit before publishing the result.
- Checkpoint and pending-dispatch records survive crash/restart. Lease expiration
  does not authorize duplicate execution until ownership is reconciled.

## Storage, retention and upgrades

App state, authorization profiles and artifacts belong under a private macOS
application-support directory; the selected repository remains user-owned.
Separate account profiles from battle instructions/worktrees. Store no credential
values, environment dumps, raw protocol frames or hidden reasoning.

Redact before writing logs; bound chunks and total growth, record truncation and
provide pagination. Keep task evidence and audit facts by default. Any retention
policy that deletes logs/artifacts is visible, scoped and must preserve active
work and completion receipts. Archive an Arena before offering permanent removal;
enumerate affected app-owned paths and never delete its original folder.

**Existing user data survives the source reset.** Do not open an older live DB
with a new schema, overwrite it or silently create a replacement over it. Use a
separate rebuild data root until a verified import/migration path exists.
Clean-install and prior-schema-copy tests, backup integrity, foreign-key checks,
failure preservation and recovery are release gates. Released migrations are
forward-only; incompatible downgrade refuses startup with a recovery path.
