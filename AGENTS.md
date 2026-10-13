@/Users/mpak/.codex/RTK.md

# Cuckoding contributor rules

These rules apply repository-wide. More specific rules may strengthen safety,
auditability and verification, not weaken them. The 2026-10-06 user reset replaces
the previous product direction. R010 implements the local foundation; provider
execution and battles remain the R020–R100 roadmap.
The current implemented boundary includes multiple named Codex/Cursor setup connections, draft planning and consented isolated
worktree preparation/inspection, summarized with
source owners in [Architecture](docs/ARCHITECTURE.md). [Plan](docs/PLAN.md) owns
remaining acceptance, not this file. Broader real-account acceptance,
repository execution and autonomous battles remain open.

Preserve these implemented contracts:

- Supported versions, observed authorization, catalog freshness, model entitlement
  and execution grants are separate. Never substitute bindings silently.
- Agents are named connections, not a singleton provider choice. Additional UUID
  records and private `agents/<UUID>` profiles remain independent. Legacy `codex`
  retains Workspace projections and `agents/codex`; do not rewrite its historical
  commands or team bindings. Scope setup receipts, model selections and planning
  to the exact connection ID, with no account/runtime/model fallback. Cursor setup
  uses only fixed version/status/models/login/logout commands, file credentials,
  empty inherited environment, disabled provider debug logging and transient provider-scoped login URLs. Cursor
  inference/planning remains unsupported until its grant is verified.
- Team revisions and scoped adoptions are immutable. Arena adoption affects new
  boards; Tabula adoption affects future planning only and waits for active
  planning. Guard both displayed scope/default revisions and retain old receipts.
- Registration reads directory metadata only. Git inspection, initialization and
  initial commit require their separate recorded intent/consent. Revalidate folder
  identity; preserve Git locks, exact byte/hash consent and uncertain partial effects.
- Drafts are scoped and revision-guarded; only Specs/ToDo are writable. ToDo is
  draft readiness, not independent review or delivery authorization.
- Draft prerequisites live in immutable revision content, projected from the
  current revision. Validate same-board references and cycles in the save
  transaction. Old history means no prerequisites; legacy saves omitting the
  field preserve existing links. Future deletion/scope changes must preserve
  graph integrity. Planning links never authorize execution.
- R040f document preview reads only explicit bounded `.md`/`.txt` selections with
  pinned native descriptors. Persist exact text/hash snapshots locally before
  provider consent. Freeze the scoped preview in the planning request; reject
  expired/foreign snapshots. Never grant the provider Arena file access or treat
  document text as policy. See [Security](docs/SECURITY.md) and [Data](docs/DB.md).
- R040l adds the explicit `folder-documents-v1` local read: docs-first eligible
  text/source snapshots, 2,000 entries, six directory levels, 16 files, 16 KiB each
  and 64 KiB total. Preserve pinned descriptors, exclusions, skip/limit counts and
  exact untruncated snapshots. Empty folders need a brief; sending snapshots still
  requires separate provider consent. No Git prerequisite or live Arena grant.
- Planning uses the assigned Speculator and fresh connection/model snapshot,
  stdin text and the existing no-tools empty-scratch grant. Import validated
  proposals into Specs once with source-command/index provenance. Cancellation
  and expired claims cannot replay usage or accept late text/results.
- New planning uses `brief-plan-v3` with up to 16 source snapshots: distinct prerequisite indices refer only to
  earlier suggestions; citation indices refer only to snapshots frozen in that
  request. Reject downgrade/malformed references before storage. Resolve imports
  through same-board receipts and preserve earlier user edits. Keep v1/v2 receipts
  readable with their original bounds; never infer missing links. A scoped citation is not proof of its truth.
- R040m freezes `card_creation: automatic-v1` in new planning consent. Commit the
  validated completion, all Specs cards, resolved prerequisites and existing
  proposal/index receipts/events in one immediate transaction. Reject expired or
  lost claims before writes; never replay inference or import on page load.
  Requests without this field retain explicit manual imports, including partial
  imports and later edits. Reanalysis appends a new graph; it never replaces tasks.
- Accepted specifications freeze a saved draft, prerequisite revisions and original
  citations in `accept_spec` before writing private Markdown. Verify bytes/hash and
  current revisions before acceptance/ToDo/history/event commit together. Never
  overwrite or replay uncertain artifacts. Later task/prerequisite edits invalidate
  current acceptance; downloads require a live session and matching file hash.
  Specification acceptance never authorizes execution or modifies Arena files.
- Project checks are explicit user-authored Arena revisions. Preview exact literal
  argv, relative directory and timeout; require fresh consent for changes/removals.
  Save revision/command/event atomically and reject stale or recovered foreign forms.
  Never infer execution permission from these declarations or consume proposed
  commands as policy. Future battle admission must freeze a revision and validate
  executable identity, owned paths and actual grants before running anything.
- Stateful LiveComponents install the shared session event guard and receive the
  server-owned session ID explicitly; parent hooks do not authorize their events.
  Preserve unsaved text and clear stale consent during live updates.
- Battle preview is a read-only observation, not a frozen battle, grant or Start
  authorization. Use the Tabula's assigned team and current revision's acceptance
  receipt; verify retained Markdown and prerequisite revisions. Mark old previews
  stale on updates/expiry. A recorded HEAD or model diagnostic never proves live
  Git cleanliness, worktree permission or task completion. Future Start still
  needs atomic authority and fresh admission; optional spec acceptance must not
  introduce ordinary per-task approval after Start.

- Worktree preparation freezes a fresh committed Git observation and source folder
  identity before native effects. Derive private destinations from command UUIDs;
  exclusively create ownership records outside detached locked checkouts. Reject
  unsafe filters/tree layouts and preserve original index/working files. Retain
  all partial effects; expired/cancelled claims cannot publish success or replay.
  Creation receipts never grant execution or prove current checkout integrity.
  Keep this setup utility separate from read-only Battle preview; future Start
  still owns ordinary worktree admission under its single bounded authorization.

- Worktree inspection binds a completed preparation and revalidates ownership,
  directory identity, detached locked registration, index entries and raw tracked
  bytes. Extra files are flagged without reading their contents. Do not trust Git
  index flags as cleanliness proof. Built-in checkout transformations can report
  differences. Keep observations dated, retain uncertain state, reject late/foreign
  receipts and never use inspection as a grant or future-integrity guarantee.

R020n task turns use only `host-task-tools-v1` dynamic list/read/edit tools.
Keep native root identity and policy-path checks, finite call/byte limits,
compare-before-write, fsynced effect receipts, cancellation and no replay.
Runtime shell/file/network tools remain disabled. R020o enables only the pure
Code Mode interpreter/router for task turns; diagnostics/planning keep it off.
State the host-service read/write grant separately from runtime scratch access;
never widen filesystem permissions to fix a model misunderstanding. Read-only
roles cannot edit. A transport
report never grants battle authority or marks a card Completed; R050 must own
that binding. Do not add a new mandatory setup diagnostic. R020o has one
consented GPT-6.1 Sol synthetic read/edit success with verified final bytes and
normal child cleanup. This is not real Arena, independent review, crash/sleep
or cross-provider acceptance; preserve those remaining gates.

R050d1 host candidate capture accepts only bounded task-tool path/hash pairs in a
verified owned checkout. Preserve the original source and task HEAD/index, verify
all other tracked bytes and modes, reject extras/protected paths, and retain
exclusive intent/index/publication/receipt artifacts and UUID-derived app refs.
Never replay uncertain capture. A dated candidate verification is neither a grant
nor independent review; future integration must bind exact criteria/check evidence.

## Mission and product contract

R020m's optional `codex-isolation-v1` diagnostic runs fixed commands against two
disposable fixtures with a fresh empty profile, never an Arena or signed-in profile.
Bind its receipt to the exact connection/version/executable observation. Preserve
explicit temporary-root denial, bounded output/deadline and owned group cleanup;
expired/cancelled work cannot publish success or replay. A dated CLI sandbox pass
does not verify model tools or authorize repository execution. Keep it optional
and outside the four required setup steps.

Build a local-first macOS menubar application opening a minimal Phoenix LiveView
UI in the default browser. Setup should take ten minutes with stated runtime/
account prerequisites. Users save agents/models and roles once. The 2026-10-10
Arena clarification makes the normal project flow **Add folder → Create tasks →
Start**. It supersedes a mandatory Tabula/Describe/setup wizard sequence.

Adding a folder uses the saved team and creates the default Tabula automatically.
Create tasks asks Speculator to analyze `docs/` and relevant eligible project files
with an optional brief, then creates validated cards without per-card imports.
Start is one execution button on that same board. Summa Rudis coordinates agents
and automatic card movement; Secutor independently judges completion and sends
review findings through Speculator. Keep custom boards/roles, check declarations,
Git/worktree details, revisions and logs in contextual Advanced/Inspect controls.
Do not require these as routine setup screens or repeat approvals per task.

R002 implements atomic default-board creation, immediate Arena navigation and
Advanced disclosures. R040l adds bounded folder snapshots and consented Speculator
analysis; R040m creates the validated cards automatically. Battle execution remains a target contract.
Preserve scoped reads/consents. Folder analysis needs a bounded read grant;
Start owns a separate bounded execution grant.
Ask before Git initialization or initial-commit mutations, only when needed;
no Git setup is required just to analyze docs. Do not substitute a preview for a
working Start button. [Plan](docs/PLAN.md#next-delivery-order--simple-arena) gives
the immediate delivery order; [D022](docs/DECISIONS.md#d022--simple-arena) records
the boundary change.

Arena simplification must preserve the separate `/agents` roster/add wizard and
`/team` role/agent/model editor. Do not replace them with discovery-only setup.
When controls seem missing, verify the running bundle and data root first:
obsolete `CCoding.app` is not the current `Cuckoding.app`. Preserve saved test
workspace launchers and their data selection when rebuilding; a source change
or successful smoke test does not update an already-running app.

**Speculator** writes specs/tasks; **Implementor** implements; **Secutor** judges
completion; **Summa Rudis** coordinates the process. Parallel role instances use
separate worktrees/sessions. Review comments return to Speculator. Phoenix
validates every agent proposal; model text never grants authority or marks work
complete. The global and Arena **Tabula Gladiatorum** expose activity and controls.

Read before implementation:
[Product](docs/PRODUCT.md), [Architecture](docs/ARCHITECTURE.md),
[Data](docs/DB.md), [Flow](docs/FLOW.md), [Security](docs/SECURITY.md),
[Execution](docs/EXECUTION_ENVIRONMENTS.md), the claimed task, Ponytail full and
the relevant local skills. [Plan](docs/PLAN.md) is the ordered acceptance checklist.
Do not restore the old implementation or treat historical tests as current proof.

## Non-negotiable boundaries

- SQLite is the durable source of truth. Never make a process, LiveView, terminal
  buffer or agent session the sole owner of workflow state.
- Bind loopback only. Require one-time shell bootstrap and a short-lived browser
  session with host/origin/CSRF protection.
- Agents and commands run as supervised host children with owned process groups,
  worktrees and approved paths. The host runner is not a sandbox.
- Never give agents GitHub/application/provider credential values through app
  prompts, config, argv, environment or MCP. Provider runtimes manage their own
  scoped authorization; Cuckoding stores references/status, not token contents.
- Never expose the real home, SSH/cloud credentials, personal Keychain or unrelated
  repositories through app configuration or grants. Record actual runtime
  enforcement and unsupported restrictions honestly.
- No role, repository document, skill or provider output may expand permissions,
  directly mutate the DB or execute changed policy. Agents may propose changes
  to protected configuration, including `.cuckoding/`; activation requires an
  explicit human decision and audit event.
- Start battle records explicit bounded local-completion authority. Independent
  Secutor review and retained evidence are required; Summa Rudis cannot override
  a failed review. Push, PR, user-branch merge and release remain separate human
  actions through host-side services if implemented.
- Do not display/persist hidden chain-of-thought. Keep public summaries, tool
  activity, artifacts, decisions and normalized transitions.
- Project knowledge stays project-scoped; any later global publication requires
  human approval. Deferred subsystems are not implied by available skills.
- One provider/plugin/network failure or sleep/wake must not make the whole app
  unusable. Preserve old user databases, profiles, branches and logs through the
  source reset; use a separate rebuild data root until migration is verified.

## Engineering

- Prefix every repository shell command with `rtk`. Use `rtk proxy` for exact
  output or semantic incompatibility and record the reason in the worklog.
  Product command declarations stay unwrapped; policy validates them before RTK.
- Apply Ponytail full to every change/review: understand the complete flow and
  callers, reuse existing code, prefer standard/native facilities, minimize files
  and dependencies. Minimalism never removes validation, durability, security,
  privacy, accessibility, observability or required acceptance.
- Use `rtk rg` and direct source inspection. No XERJ/indexing requirement.
  For unfamiliar work follow [reference coding](docs/REFERENCE_CODING.md), check
  peer licenses and record the source revision and `path:line`.
- Use explicit supervised OTP components and behaviours at implemented replaceable
  boundaries: runner, adapter, secret store, VCS host, metrics collector, plugin
  kinds and knowledge backend. Do not scaffold deferred subsystems.
- Make commands idempotent with stable keys and expected revisions. Write events
  and state transactionally before broadcast. Reconcile uncertain external
  effects before retry; never claim exactly-once external execution.
- Use worktrees for concurrent isolation, process groups and per-run ports.
  Exclusive resources use TTL/heartbeat leases; reconcile sleep gaps before
  expiring/reassigning live ownership. Persist UTC time and measured monotonic
  durations with explicit sleep gaps.
- Keep provider payloads bounded and redacted only when needed for diagnosis;
  normalize business fields. Never label inferred usage/cost/savings measured.
- Version workflows, role/team bindings, grants, configuration and artifacts.
  Frozen battle snapshots remain immutable; settings updates affect future work.
- Executable discovery reads known locations/metadata only. Manual overrides,
  supported-version probes and app-owned authorization remain distinct. Host
  discovery hints never become child environment or filesystem grants.
  The native fixed `--version` probe uses a private scratch directory, empty
  inherited environment, bounded output and owned group cleanup. Interrupted
  probes and connection inspections require a new consented command; never replay
  them as metadata discovery. The fixed Codex app-server inspection permits only
  initialize/config-read/account-read/model-list, keeps raw frames and account
  identifiers out of Cuckoding storage, and rejects unsafe profiles. Keep the
  explicitly selected executable: desktop and standalone Codex can advertise
  different catalogs. Verified versions are 0.146.0, 0.162.0-alpha.2 and 0.162.0-alpha.17.2. Allow
  `account/updated` during authoritative `account/read` only; unsolicited login
  completion, server requests and later account drift remain refused. Retain the
  last catalog as stale after inspection failure; age it out after 24 hours.
  Fetch the full bounded agent catalog, including entries hidden from its default
  picker. Validate/preserve that flag and expose additional models without
  inventing IDs or inferring entitlement; older cached rows remain readable.
  Cursor catalogs permit up to 512 rows within the fixed 64 KiB stdout limit;
  retain every advertised variant. Saved selections permit up to 512 catalog-bound
  IDs. Reject malformed/partial/duplicate/over-limit lists without publishing a
  truncated fresh catalog.
  Login/logout invalidate account/catalog observations before launch and require
  separate consent. Serialize profile operations through the ledger and native
  lock; never replay interrupted authentication. Hold cancellation until helper
  exit/cleanup or report uncertainty. Keep validated login URLs transient and
  behind the session-protected redirect, never in LiveView assigns, SQLite or logs.
  The model diagnostic requires separate usage consent, a fresh identity/catalog
  snapshot, verified restrictive effective config and one fixed prompt. Reject
  model drift, tool activity and foreign completion. Ignore bounded informational
  warning/deprecation notifications without storing their text; requests and account
  drift remain refused. Persist only the public
  receipt; keep requested/runtime model separate. Hold cancellation through
  cleanup and never replay interrupted inference. This grants no repository work.
- Inspect processes by executable, PID/start identity, working directory and
  listeners. Never dump raw argv/environments. Redact before logs/UI/artifacts.
- For a requested restart follow [Development](docs/DEVELOPMENT.md): identify only
  owned instances, shut down gracefully, preserve data, verify cleanup, then
  launch one chosen build. Never kill unrelated provider apps.

## UI

For source UI development use `rtk proxy bin/dev.server` after building the native
helper. Phoenix LiveReload and its iframe CSP exception must remain dev-only.
The launcher retains the normal bootstrap/session/heartbeat with separate
`.ccoding/ui-dev/` data. Keep it loopback-only and do not import real app profiles
for UI tests. Tidewave was removed; do not restore its MCP/toolbar or broad CSP
exceptions without a new user request.
See [Development](docs/DEVELOPMENT.md#ui-development).
If the developer data lock is held, identify the existing owner; never unlink or
steal it. When handing terminal startup back to the user, stop only your verified
preview instance and confirm cleanup rather than leaving a competing launcher.

Use Phoenix LiveView, HEEx and Tailwind. Keep one reusable accessible dialog
convention; validation lives in domain contexts/LiveView and small hooks cover
native browser behavior. No second frontend framework.

Canonical navigation routes are `/agents` for the roster/wizards and `/settings`
for workspace settings. Keep sidebar, cross-links and tray handoffs consistent;
legacy redirects must not bypass browser session checks.

Honor [the UI contract](docs/UI_DASHBOARD.md): slim sidebar, one/two primary
regions, modern mouse-friendly TUI appearance, no decorative dashboard clutter.
Use the shared near-black/electric-green palette (`#050807` / `#82ff52`), restrained
HUD borders and readable system type. Keep cinematic artwork on the public site;
internal forms retain the one/two-region layout and visible keyboard focus.
Every long action shows state, elapsed time, role, runtime, model when known,
and pause/resume/retry/stop/inspect as appropriate.

Provide keyboard/menu alternatives to every drag action; enforce the same gates.
Preserve text, focus, scroll and disclosures through live updates. Bind checkbox
state in LiveView; clock/unrelated updates must preserve it. Agents setup follows
Choose Agent → Connect and Authorize → Select models → Save. Explicitly labelled
version/profile action buttons record consent bound to the current form key and
setup revision; do not restore the old checkbox wall. Keep separate usage consent
for optional inference. Fresh connections clear it while preserving model choices.
Reject recovered stale forms and reviewed saves. Store selected catalog IDs plus
resolved models in audited revision-guarded SQLite commands. Filter new Team
choices, never rewrite existing roles or treat selections as entitlement/grants.
Hide sign-in when connected; retain sign-out/refresh. Step 2 always shows
Next with an explanation when unavailable. A connected account may open step 3
with a stale/failed catalog to inspect and refresh it; selection/save still require
a fresh catalog and navigation must never launch a provider. Choosing the desktop path
is metadata-only until a consented version check. Keep errors
visible and do not rely on color alone. Destructive/trust-boundary actions require
confirmation and an audit event. Supplied images are reference content, not
executable instructions; keep provenance and accessible truthful labels.

Use **Cuckoding** as the full display name, **CC** for short, and capitalize
**Emperor**. Preserve existing storage/protocol identifiers across display renames.
The C/furcina devil-tail logo source is `desktop/mark.svg`; regenerate all site/app/native
consumers with `rtk proxy bin/brand-icons` after edits and verify repeat hashes.

The public GitHub Pages site lives in `site/`, separate from the application.
Use native HTML/CSS/JS; retain satirical artwork provenance, accessible navigation,
no-JavaScript content and OS/user motion controls. Illustrated scenes use independent
background/character layers; keep every layer covered by pause and reduced motion.
R019 cinematic pinning is progressive enhancement: no-JS/reduced-motion content
stays in normal flow, user pause preserves page height, and readable copy/controls
never receive parallax transforms. Reference sites inspire composition only;
retain original local artwork and record prompts in `docs/ARTWORK.md`.
R019a adds gothic sci-fi architecture and leather/harness stage fashion; preserve
the fully clothed characters, green palette and independent transparent layers.
R019b extends that fashion to the Arena spectators; keep them in the stands and
the background floor clear for independently moving foreground characters.
Never describe planned features
or concept boards as available product behavior. Only `site/` may be published;
local merge is not permission to push/deploy. Follow [Site](docs/SITE.md), run
`rtk proxy python3 bin/check-site` and `rtk proxy node --test test/site_test.mjs`,
and inspect desktop/narrow rendering for site changes.

## Database and verification

Keep the locked Decimal dependency at 3.1.2 or newer (R101, CVE-2026-97853);
integer-based accounting remains unchanged.

SQLite uses WAL, foreign keys, busy timeout and short transactions. Keep immutable
historical facts in events/attempts and current projections separate. Released
migrations are forward-only and tested against prior-schema copies with verified
backups. Never overwrite an old DB to make the rebuild boot. Tokens/bytes are
integers; money uses integer micros plus currency.

Every behavioral change needs a focused runnable regression check. Documentation/
metadata changes use structural, reference and claim validation instead of
invented product tests. Before completion use quality-gates and the relevant
subset in [Testing](docs/TESTING.md): Elixir format/compile/warnings/tests/static
analysis; Rust format/lints/tests; migration/crash; paths/commands/canaries;
sleep/reconciliation; adapter/plugin conformance; LiveView accessibility/end-to-
end; native clean-machine packaging. Record exact commands/results in worklog.
Absent checks are unavailable, never passing.

Current commands: `rtk mix quality`; `rtk cargo fmt --manifest-path
desktop/src-tauri/Cargo.toml --check`; `rtk cargo clippy --manifest-path
desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`; `rtk cargo
test --manifest-path desktop/src-tauri/Cargo.toml --locked`; `rtk proxy
bin/dev.build`. See [Development](docs/DEVELOPMENT.md) for the bundled smoke test
and private rebuild data location. Run commands from the repository root with
the pinned toolchains; do not start the release without its native handshake.

## Task protocol

1. Claim exactly one task file and add a worklog.
2. Restate its acceptance criteria and inspect code/dirty state before edits.
3. Make the smallest coherent change; preserve unrelated edits.
4. Add focused checks and durable public events for behavior.
5. Update affected docs/decisions in the same change.
6. Verify and check completed items only with evidence. Distinguish working tree,
   local commit, remote publication, native build and actually running artifact.
   Fixture tests and historical ports/PIDs are not current provider acceptance.
7. Leave an explicit handoff for blocked/partial work.
8. After every completed task or plan slice, commit it and merge into local
   `main` after verification. Always update the relevant `docs/`, `AGENTS.md` and
   `README.md` with the resulting scope/status and instructions. Record unavailable
   checks honestly; never infer permission to push/publish from local integration.

Branches: `feature/<task-id>-<short-name>` or `fix/<task-id>-<short-name>`.
Commits: `<type>(<area>): <imperative summary>`. Keep one task per branch.
Commit required generated files/migrations/config snapshots for reproducibility.

Use [Skills](docs/SKILLS.md): Ponytail for every change/review; quality-gates
before completion; local-runner for worktrees/processes/power; agent-adapter for
runtime integration; security-review for execution, credentials, paths, processes,
networks, updates or publication. Use plugin-system or knowledge-compression only
when implementing that explicitly scoped work.

## Stop conditions

Request a human decision for exposed secrets; access beyond grants; undeclared
plugin host access; conflicting uncommitted user edits; irreversible migration
risk; indistinguishable untrusted output/trusted commands; or publication that
could expose another project/person/organization. The user's recorded intentional
source deletions are not an instruction to restore them.
