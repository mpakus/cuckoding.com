@/Users/mpak/.codex/RTK.md

# Cuckoding contributor rules

These rules apply repository-wide. More specific rules may strengthen safety,
auditability and verification, not weaken them. The 2026-10-06 user reset replaces
the previous product direction. R010 implements the local foundation; provider
execution and battles remain the R020–R100 roadmap.
R020a–d add Codex version readiness, private-profile inspection, validated model
caching, managed ChatGPT login/logout and a fixed consented model-access check.
Human-completed real-account/model acceptance and repository turns remain open. A supported version or catalog is not
model entitlement or an execution grant. Preserve separate observations and
fresh executable/profile confirmation. R030a adds configuration-only saved teams:
immutable revisions, four required responsibilities and up to eight custom roles.
Saving never grants execution. Custom roles stay planning-only/read-only; no
schedule or grant control exists yet. New model bindings require a fresh verified
catalog; retain unchanged bindings through disconnect/drift without substitution.
Team commands use team revision IDs, independently of setup workspace revisions.
R040a registers canonical Arena folders through a bounded native chooser and
separate confirmation. Freeze the displayed team revision; recheck directory
identity before registration. Git-entry presence is unverified metadata only.
Never infer file/execution grants or run Git from registration. Folder commands
must not mutate provider workspace revisions or replay interrupted dialogs.
R040b adds immutable default Tabula definitions and revisioned manual task drafts.
Copy the Arena's team reference, never the latest global default. Draft saves are
scoped to Arena/Tabula/task, guarded by task revisions and committed with history
and events. Only Specs/ToDo are writable; ToDo requires description and criteria.
Neither stage grants execution or represents a validated Secutor result. Preserve
recovered-form identity guards and unsaved text through live updates.
R040c adds explicit Arena Git inspection and separately confirmed initialization.
Bind init to the latest missing observation (under five minutes) and pinned folder
identity. Initialization never stages/commits files. Never adopt linked/external metadata, inherit personal
Git config or replay uncertain effects. Fixed native Git operations reuse the
command ledger and owned group cleanup; their result is not an execution grant or
proof of a clean worktree. R040d adds separately authorized initial commits only:
bind fresh consent to exact selected paths, byte hashes, modes and repository/branch
identity; refuse existing indexes/refs and never overwrite working files. Keep
HEAD/index/ref locks, retain partial effects and never replay uncertain writes.
Preview metadata is bounded; events omit paths/content/hashes. No push, agent grant
or battle is implied. See the Git limits in `docs/SECURITY.md`.

R040e permits one separately consented brief-only Speculator turn using the
Tabula's frozen team and fresh connection/model binding. Reuse the no-tools,
empty-scratch grant; briefs/instructions travel over stdin, never argv. Persist
only bounded public proposals and receipts. Import suggestions into Specs once
with source-command/index provenance; never interpret prose as authority.
Cancellation and expired claims cannot replay usage or import a late result.
This is not file-backed planning or a battle execution grant.

## Mission and product contract

Build a local-first macOS menubar application opening a minimal Phoenix LiveView
UI in the default browser. Setup should take ten minutes with stated runtime/
account prerequisites. Users save agents/models and roles once, create an Arena
and Tabula, describe work, then Start battle.

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
  them as metadata discovery. The fixed app-server inspection permits only
  initialize/config-read/account-read/model-list, keeps raw frames and account
  identifiers out of Cuckoding storage, and rejects unsafe profiles. Retain the
  last catalog as stale after inspection failure; age it out after 24 hours.
  Login/logout invalidate account/catalog observations before launch and require
  separate consent. Serialize profile operations through the ledger and native
  lock; never replay interrupted authentication. Hold cancellation until helper
  exit/cleanup or report uncertainty. Keep validated login URLs transient and
  behind the session-protected redirect, never in LiveView assigns, SQLite or logs.
  The model diagnostic requires separate usage consent, a fresh identity/catalog
  snapshot, verified restrictive effective config and one fixed prompt. Reject
  model drift, tool activity and foreign completion. Persist only the public
  receipt; keep requested/runtime model separate. Hold cancellation through
  cleanup and never replay interrupted inference. This grants no repository work.
- Inspect processes by executable, PID/start identity, working directory and
  listeners. Never dump raw argv/environments. Redact before logs/UI/artifacts.
- For a requested restart follow [Development](docs/DEVELOPMENT.md): identify only
  owned instances, shut down gracefully, preserve data, verify cleanup, then
  launch one chosen build. Never kill unrelated provider apps.

## UI

Use Phoenix LiveView, HEEx and Tailwind. Keep one reusable accessible dialog
convention; validation lives in domain contexts/LiveView and small hooks cover
native browser behavior. No second frontend framework.

Honor [the UI contract](docs/UI_DASHBOARD.md): slim sidebar, one/two primary
regions, modern mouse-friendly TUI appearance, no decorative dashboard clutter.
Every long action shows state, elapsed time, role, runtime, model when known,
and pause/resume/retry/stop/inspect as appropriate.

Provide keyboard/menu alternatives to every drag action; enforce the same gates.
Preserve text, focus, scroll and disclosures through live updates. Keep errors
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
background/character layers; keep every layer covered by pause and reduced motion. Never describe planned features
or concept boards as available product behavior. Only `site/` may be published;
local merge is not permission to push/deploy. Follow [Site](docs/SITE.md), run
`rtk proxy python3 bin/check-site` and `rtk proxy node --test test/site_test.mjs`,
and inspect desktop/narrow rendering for site changes.

## Database and verification

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
