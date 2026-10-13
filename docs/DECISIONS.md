# Current decisions

Accepted product reset: 2026-10-06. Earlier ADRs remain in Git history; they do
not establish implementation or acceptance of this rebuild.

| ID | Decision | Reason / consequence |
| --- | --- | --- |
| D001 | Keep Elixir/OTP, Phoenix LiveView/Tailwind, Ecto/SQLite, Git worktrees and Tauri 2 | User requested the same stack; no replacement frontend/control plane |
| D002 | Arena = project, Tabula = board, battle = execution, Tabula Gladiatorum = global/Arena dashboard | One consistent product vocabulary; Area interpreted as Arena |
| D003 | Speculator → Implementor → Secutor; distinct Summa Rudis coordinator | Separate planning, writing, completion judgment and coordination |
| D004 | One Start action authorizes bounded ordinary local work | No competing manual/prepared/project start modes or repeated task approvals |
| D005 | Phoenix validates agent proposals; SQLite owns durable state | Model output cannot command the host or fabricate completion |
| D006 | Parallel task workers; serialized reviewed battle-branch integration | Deliver concurrency without shared writable worktrees or stale-review acceptance |
| D007 | One active battle per Arena initially | Keeps integration ownership simple; independent Arenas/tasks still run concurrently |
| D008 | Ordered custom columns/roles with mandatory final review | Meet extensibility need without a general workflow graph editor |
| D009 | Readable Markdown specs/evidence, scoped file search, RTK and Ponytail full | No XERJ, embeddings service, plugin marketplace or autonomous memory pipeline |
| D010 | Source reset preserves old application data; use a separate rebuild data root | No inferred permission to destroy databases/profiles/worktrees |
| D011 | Ten minutes from first launch to ready with runtime/account prerequisites stated | Measurable setup target; also report full installation timing |
| D012 | Provider capabilities require per-version real evidence | Named runtimes are targets, not unsupported promises; transport stays adapter-specific |
| D013 | Append-only scoped team adoptions override creation defaults for future work | Explicit confirmation and revision guards; Arena changes affect new boards, Tabula changes affect new planning, historical receipts stay unchanged |
| D014 | Explicit selected-document snapshots feed the existing no-tools planning turn | Local preview reads bounded text using pinned descriptors; separate provider consent freezes the scoped snapshot reference. Documents are untrusted evidence, never filesystem or execution authority |
| D015 | Draft prerequisites live in immutable draft revision content | Reuse the existing save transaction and current-revision projection; validate same-board references and acyclicity before saving. No scheduler or new execution authority is implied |
| D016 | New Speculator proposals reference earlier tasks and selected snapshots by bounded indices | A versioned contract binds references to the frozen request; import resolves prerequisites through same-board receipts and retains source provenance. No arbitrary path, task ID or execution authority comes from provider output |
| D017 | Accepted specs freeze task and prerequisite revisions before writing private Markdown | Reuse durable command receipts and draft history. Verify the file and revisions before atomic acceptance/ToDo; keep stale or interrupted artifacts, never overwrite or auto-replay them. Acceptance grants no execution |
| D018 | Save approved check declarations as immutable Arena revisions before battle execution | Explicitly preview literal argv, relative working directory and timeout; confirm changes/removals and audit atomically. Configuration never grants execution or proves a command safe. Future Start snapshots the revision and validates executable/worktree/runtime grants |
| D019 | Prepare detached locked worktrees through the existing consented Git ledger | Freeze fresh HEAD and folder identity before a fixed native operation. Keep ownership outside checkout, reject unsafe checkout mechanisms and bounded tree violations, retain interrupted effects. This is a setup utility, not battle admission or execution authority; Battle preview stays read-only |
| D020 | Inspect retained worktrees against their preparation receipt | Use the existing Git ledger to verify private ownership, detached locked registration, index entries and raw tracked bytes without mutation. Extra files are flagged without reading their contents. Built-in checkout transformations can report differences; this conservative dated observation is not execution authority or future cleanliness proof |
| D021 | Save independent named agent connections; retain legacy Codex identity | UUID-scoped profiles, commands, catalogs and selected models let each role choose its own agent/model. Keep the original `codex` projection/profile and immutable bindings readable; never fall back across connections. Setup stays serialized. Cursor setup does not enable inference |

| D022 | Add folder → Create tasks → Start on one Arena board | Reuse saved team, create the default board automatically, analyze bounded folder sources and create validated cards without mandatory per-card imports; one bounded Start covers ordinary work and independent review |

## D021 · Named local agent connections

Accepted 2026-10-10 for R020i.

An agent is a saved connection, not a global provider choice. Additional connections
have UUIDs, names, runtime kinds, version and account/catalog projections in SQLite.
Commands freeze that ID; native profiles derive from it, never a browser path.
The legacy `codex` ID keeps Workspace's existing projection and `agents/codex`
profile so old commands and immutable team bindings remain valid without rewriting.
The same domain API serves both. New role bindings retain the connection ID and
resolved model. No fallback to a different account, runtime or model is permitted.

The existing dispatcher remains globally serialized for bounded setup operations;
separate records/profiles do not claim parallel execution. Saved model selections
remain audited command snapshots, now scoped to connection ID. Cursor setup uses
only fixed version/status/models/login/logout commands in an app-owned file-backed
profile. Cursor inference/planning remains unavailable until its permission grant
is verified; saving a mixed team never grants execution.

The first release scope and deferred features are in [Product](PRODUCT.md).
[Flow](FLOW.md) owns state, defaults and limits. Changes to settled boundaries
must update this file before implementation and preserve the user-approved scope.

## D022 · Simple Arena

Accepted 2026-10-10 from the user's original story and Arena simplification.
Agents/Team are saved once. Adding a folder creates a default Tabula and opens it;
Create tasks uses the saved Speculator, an optional brief and bounded project
sources. Validated proposals become cards automatically. Start runs the same
board with Summa Rudis coordinating and Secutor judging completion. Advanced
holds additional boards, role/column configuration and technical inspection.

This supersedes mandatory separate Tabula/Describe/setup screens, not authority
or evidence requirements. D014's selected-snapshot implementation stays valid
until a versioned bounded folder-analysis contract replaces it. D017 acceptance
and D019/D020 setup utilities remain optional; battle admission still validates
fresh state. No routine per-task approval follows Start. Git initialization and
initial commit retain explicit consent when needed; read-only planning needs no Git.

Use existing Arenas/Tabulae/Planning contexts and command/event transactions.
No new frontend, queue or database. Add-folder/default-board persistence must be
atomic and idempotent; existing boards/history survive. Target automatic analysis,
card creation and execution remain open in [Plan](PLAN.md#next-delivery-order--simple-arena).

## D023 · Executable-bound isolation evidence

Accepted 2026-10-13 for R020m. Before enabling repository turns, verify the selected
Codex version's sandbox with fixed commands in disposable private fixtures. Use
the existing consented command ledger, executable identity and owned process
cleanup; retain only normalized check results. Explicitly deny temporary roots
and private profiles rather than assuming minimal-system access excludes them.
The optional Agents diagnostic does not touch an Arena, use an account/model,
or authorize work. Its success cannot substitute for a fresh battle grant,
effective thread policy, model tool validation or independent Secutor review.

## D024 — Host-owned task tools

Accepted 2026-10-13, before R020n implementation. The first coding turn retains
Codex's empty-scratch, built-in-tools-disabled grant and supplies only bounded
dynamic list/read/edit tools implemented by the host. This avoids giving model
text a general shell bridge. The host validates one frozen worktree identity,
relative eligible paths, byte/call limits and expected content hashes; protected
policy/credentials and other folders remain inaccessible. Tool effects retain
private receipts, while SQLite remains the attempt/authority owner. Independent
review receives only read tools. Host check declarations execute through a
separate bounded runner, never through proposed shell text.

This is actual file-tool execution, not a model response interpreted as a patch.
It supports the initial code-editing flow with finite text-file limits; commands,
binary editing and protected configuration are outside this grant. Full runtime
and two-workspace acceptance must still be measured, not inferred from schemas.

## D025 — Host-captured task candidates

2026-10-13. R050d1 extends the fixed native Git service with candidate capture and
verification. The host supplies exact bounded path/hash pairs from completed task
file-tool receipts; provider text never supplies Git argv or reference names.
A private candidate index preserves unchanged base objects. All other tracked
bytes and file modes must still match the prepared base; extra entries and policy
changes fail closed. Candidate objects and a UUID-derived application reference
are retained without updating the source checkout/index/branch or detached task
HEAD. An exclusive attempt directory records intent before effects; uncertain
attempts are inspected, never replayed. Verification compares the exact retained
candidate tree against live bytes. Start authority, check execution, independent
Secutor verdicts and reviewed integration are separate R050d/e responsibilities.
