# Data model

Target schema, to be implemented incrementally. Use Ecto and SQLite with WAL,
foreign keys, a busy timeout and short write transactions. Persist workflow
truth here; files store human-readable content and processes do the work.

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
