# Data model

R050a's Battle preview adds no table or persisted workflow state. It reads existing
team adoption, draft revision/acceptance, check revision and Git command receipts
in one read transaction. Artifact verification describes bytes at observation
time. No battle membership, approval or execution evidence is inferred or saved.

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
R020f requests the full runtime list and stores its boolean `hidden` picker flag
per model. Older rows may omit it; no migration or binding rewrite is needed.
Hidden entries remain selectable and are labeled additional, not access-verified.
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
R030b adds scoped adoption of saved defaults (below); per-scope role editing,
schedules and executable grants are not implemented.

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

`create_tabula` copies the currently assigned Arena team, even after global defaults change.
`save_draft` atomically commits the current projection, immutable history and
`draft.saved` event; a failed event rolls back all writes. Matching keys return
the original revision receipt. Scope/stale/stage/readiness rejections are durable.
Events include IDs, revision and old/new columns, never task prose. Neither
command touches setup revisions or enters the dispatcher. Title/description/
criteria limits are 120/8,000/4,000 characters; ToDo needs nonblank description and
criteria. The UI reads the latest five revisions; older history stays in SQLite.
These saves create database drafts. R040i separately accepts a saved revision as
a file-backed specification; manually moving to ToDo does not create acceptance.

R040g adds `depends_on` to revision content, with up to sixteen distinct canonical
task UUIDs from the same Tabula. It adds no migration or persisted projection
column: `Tabulae.tasks/1` joins the current revision and populates a virtual field.
Missing fields in old history read as `[]`; old rows/command payloads are never
rewritten. Saving without this optional field preserves current prerequisites;
an explicit `[]` clears them. Legacy v1 imports begin with `[]`; v2 imports
resolve proposed dependencies as described below.

The immediate save transaction rejects self, missing, cross-board and cyclic
links against the latest board graph. This also catches a cycle introduced by
another task changing after the editor opened. Rejections retain the original
task/history; `draft.saved` includes dependency IDs but no prose. No task deletion
or board reassignment is available; future commands must enforce these graph
invariants too. These links are planning facts, not execution readiness.

R040h adds the versioned `brief-plan-v2` response contract without a migration.
Each of 1–6 suggestions has title/description/criteria plus distinct `depends_on`
and `sources` integer arrays. Dependencies reference earlier zero-based suggestion
indices; sources reference the 0–4 selected snapshots in the frozen request.
Self/forward/cyclic/duplicate/missing/out-of-range references and v1-shaped answers
to v2 requests are discarded before proposal storage. Old v1 requests/receipts
keep their three-field tasks and remain importable without invented citations.

`import_plan_task` resolves prerequisite indices to UUIDs using completed import
commands from the same proposal and Tabula, inside its immediate transaction.
Missing imports record `prerequisites_not_imported`; retry uses a fresh command
key. Imported tasks never overwrite an earlier imported task's edits. The draft
revision stores resolved UUIDs; the import's proposal/index link retains original
citations. UI citations show the exact stored path/text/hash, not current files or
evidence that later edits are supported. `planning.completed` adds dependency and
citation counts only; source text and paths stay out of events.

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

R040d adds `preview_arena_git` / `commit_arena_git` in the same ledger/schema.
Preview stores bounded selected paths, sizes, modes, SHA-256 and a repository
fingerprint (Git directory identity, branch and config digest), never file bytes.
Commit copies the latest preview and its command ID after fresh explicit consent;
idempotency includes selected paths/preview identity. Matching completion carries
head/tree and preview ID. Events keep IDs, closed statuses and measured duration;
paths/hashes/content stay out of events. Expired or foreign receipts fail closed.
SQLite and filesystem publication are not atomic; uncertain claims never replay.

The default native root is `~/Library/Application Support/CCoding Rebuild`,
marked `.ccoding-rebuild-v1`. Unknown nonempty roots and symlinked storage are
refused before migration. `foundation.db` and sidecars are private; old Cuckoding
data is not opened. `CCODING_DATA_DIR` can select an absolute isolated test root.

## R030b scoped team adoptions

The seventh migration adds append-only `team_adoptions`: integer sequence, Arena
ID, optional Tabula ID, saved team revision FK, unique command ID and UTC time.
A composite index selects the newest entry per scope; absent adoption falls back
to the immutable creation reference. SQLite refuses rewrites/deletion and foreign
Arena/Tabula pairs. Prior schema rows need no rewrite or inferred adoption.

`adopt_team` records explicit confirmation, previous scope revision and target
saved default revision. An immediate transaction validates both revisions, scope
and lack of pending/running/cancelling planning for a Tabula, then records adoption
and `team.adoption_completed`. Rejections are durable and idempotent with
`team.adoption_rejected`; events contain IDs/reasons, not role instructions.
The command never enters the dispatcher or changes provider workspace revisions.
Arena adoption affects only subsequently created Tabulae. Tabula adoption affects
new planning consent/snapshots; creation references, earlier requests and draft
history remain unchanged. The UI shows the last five adoptions; all remain stored.

## Target records (not the current schema)

| Record | Durable fields / invariant |
| --- | --- |
| Agent connections | Runtime key, executable identity/version, provider-owned profile reference, observed authorization state/time; no tokens |
| Model catalog | Connection/runtime scope, model ID, label, capabilities, source, fetched time, freshness/error status |
| Role definitions and team revisions | Stable role ID, display name, instructions, connection/model, grant, coordinator binding, revision |
| Arenas | Canonical repository path, name, selected base ref, trusted settings revision |
| Tabulae and workflow revisions | Arena, ordered columns/keys, role bindings, entry/exit contracts, limits |
| Specs | R040i implements scoped revision snapshots, source paths/hashes and Markdown via commands; per-criterion IDs and battle binding remain |
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

## R040e planning receipts

No schema change. `plan_tabula` commands retain the explicit brief, setup-consent
fingerprint, immutable team/Speculator snapshot, executable identity, connection
observation, model/effort and `brief-plan-v1` contract. A matching completion adds
only its validated public proposal and thread/turn/grant/timing receipt to
`payload.observation`. Status/events contain IDs, counts and timing, never prose,
raw frames or hidden reasoning. Invalid/cancelled/interrupted results cannot import.

`import_plan_task` stores the source command ID and zero-based suggestion index.
An immediate SQLite transaction rejects duplicate imports even with a different
command key; the same key replays its saved revision. Draft task, revision and
provenance events commit atomically. Later user edits append normal revisions.
The UI shows the five recent requests (active first); older receipts remain in SQLite. These
records are not approved Markdown specs, execution policy or completion evidence.


## R040f selected document snapshots

No migration; seven versions remain. `preview_documents` stores Arena/Tabula IDs,
selected paths and registered directory identity before a bounded local read.
Its 25-second claim covers the 15-second native reader and cleanup. A matching
completion stores exact text, relative path, byte count and SHA-256 in
`payload.observation.files`. Known errors omit file content. Completed snapshots
are retained as historical facts; cancellation/expired claims reject late reads
and never automatically replay. Workspace provider revisions are unaffected.

At consent, `plan_tabula` includes `document_preview_id` and a frozen `documents`
list. Only a completed, matching-scope preview less than five minutes old can be
selected; the setup fingerprint also binds its content. Earlier brief-only rows
remain readable. Later file edits cannot silently alter the requested snapshot;
old planning results remain importable after preview expiry. Import provenance
links draft revision → proposal command/index → preview ID and exact text/hash.
This is source-set provenance, not validated per-task citations or accepted specs.

## R040i accepted specifications

No migration. `accept_spec` snapshots format version 1, Arena/Tabula/task IDs,
source draft revision/content, prerequisite IDs/revisions, original proposal/index
and cited snapshots, exact Markdown and SHA-256. Description and criteria must be
nonempty. Confirmation binds the preview hash; scope, task and prerequisites are
revalidated before enqueue and completion. Matching keys return the saved receipt.

The dispatcher writes `specifications/<command UUID>.md` beneath private app
storage, using exclusive creation, private permissions and a synced file. It never
overwrites or writes into the Arena. Completion verifies bytes/hash, then commits
the accepted receipt, draft revision +1, ToDo projection and events atomically.
The normal draft history row references the acceptance command. No DB transaction
is held during writing; a failed completion may leave a retained unaccepted file.
The ten-second claim expires to interrupted without replay, and cancellation
cannot accept a late write. Retry uses a new key/file; all prior files are retained.

Current acceptance requires the exact resulting task revision and prerequisite
revisions. Even a save that returns to old text invalidates the previous acceptance.
The UI shows the five most recent requests; all command receipts/files remain.
Authenticated downloads resolve only a completed acceptance ID and verify its hash;
missing/changed/unsafe files are refused. A new acceptance can replace an unavailable
artifact without overwriting it. File-backed intent is not tested completion or
execution policy. `spec.*` events retain scope/revision/status/measured duration;
task text, source paths and Markdown stay out of events.

`documents.*` events record scope, status, file count and measured elapsed time,
never paths, hashes or prose. Selected text is intentionally retained in the private
local DB and sent only by separate planning consent; it is not secret-scanned.

## R040j project check declarations

The eighth migration adds append-only `check_revisions`: Arena FK, unique command
FK, per-Arena consecutive revision, versioned definition and UTC timestamp. A
unique Arena/revision index and sequence trigger reject duplicate/skipped revisions;
update/delete triggers preserve all earlier definitions. Old Arenas have implicit
revision 0 with no checks; the migration does not invent approval or rewrite data.

`save_checks` validates a closed declaration schema and records explicit confirmation,
expected revision and definition in a completed/rejected command. An immediate
transaction saves revision +1 and `checks.completed` together, or records a closed
`checks.rejected` reason. Matching keys return the original receipt; changed keys'
inputs conflict, and stale writers cannot replace newer settings. These synchronous
configuration commands never enter dispatch or change provider/workspace revisions.

Format 1 contains `execution: disabled` and 0–8 checks, each with a canonical UUID,
unique case-insensitive name (1–60 characters), executable basename (1–80 ASCII
bytes, no RTK wrapper), up to 16 nonempty literal arguments (256 UTF-8 bytes each),
a worktree-relative directory (240 bytes, `.` permitted, no traversal/empty parts/
backslashes/home expansion), and integer timeout 1–1,800 seconds. Extra keys,
controls and malformed inputs are refused. Empty lists explicitly remove configured
checks; they never represent successful verification. Names/arguments are stored
locally, escaped in the UI and omitted from events. Events contain Arena ID,
previous/resulting revision, check count and closed reason only.

The UI exposes the latest five immutable revisions; older rows remain in SQLite.
Preview binds exact normalized fields before confirmation. Future battles must
snapshot an explicit check revision; changing configuration cannot mutate a saved
battle or imply permission to execute. Runtime grants and check receipts do not
exist in this slice.

## R050b worktree receipts

`worktree_arena_git` reuses commands/events; schema remains at eight migrations.
Intent freezes Arena ID, source path/device/inode, observation ID, exact HEAD and
`<data>/runtime-home/worktrees/<command UUID>/checkout`. A completed public receipt
retains command key, HEAD, checkout path/device/inode and measured duration.
Events contain only scoped IDs, operation, status and elapsed time; no source paths
or contents. Native `owner.json` beside the checkout stores version, key, HEAD,
source device/inode and destination, exclusively before Git effects. It is an
ownership aid, not a live integrity check or a substitute for the DB command.

Pending cancellation launches nothing; running cancellation holds ownership until
cleanup. An expired running claim rejects late success, then becomes interrupted
without replay. Partial directories and Git registrations remain. The UI shows
the latest ten attempts; older receipts remain in SQLite. No auto-prune/delete or
battle membership/grant is created. `ArenaGit.latest/1` excludes worktree attempts
so a creation receipt never becomes the source repository's latest observation.

## R050c worktree observations

`inspect_worktree_arena_git` freezes an Arena-scoped completed preparation's key,
HEAD, checkout path/device/inode in `payload.preparation`; `observation_id` points
to that preparation. The source folder identity is frozen independently. Idempotent
requests retain the original receipt; no schema change or mutable worktree projection.

Closed results distinguish `worktree_unchanged`, `worktree_changed` and refused or
interrupted observations. Unchanged/changed inspections complete successfully as
observations, not task completion. Receipt fields must match the frozen preparation.
Cancellation strips late observations; expired claims cannot publish success and
are never replayed. Events carry only operation/status/elapsed/scoped IDs; neither
file contents nor untracked names are persisted. The latest inspection accompanies
each of the ten visible preparations; older commands/events remain in SQLite.
`ArenaGit.latest/1` excludes both worktree operations.
