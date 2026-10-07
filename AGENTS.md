@/Users/mpak/.codex/RTK.md

# Cuckoding contributor rules

These rules apply repository-wide. More specific rules may strengthen safety,
auditability and verification, not weaken them. The 2026-10-06 user reset replaces
the previous product direction. R010 implements the local foundation; provider
authorization, roles, Arenas and battles remain the R020–R100 roadmap.

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
  scoped authorization; CCoding stores references/status, not token contents.
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
