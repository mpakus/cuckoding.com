# Testing Strategy

## Principles

- Every behaviour has a fake implementation used by core tests; real tools run only in opt-in integration suites.
- Tests that touch time use injected continuous-monotonic, uptime, and wall sources. Sleep gaps are continuous-minus-uptime divergence; wall time supplies UTC timestamps and must not trigger a gap by itself.
- Failure evidence is preserved: run/event IDs, redacted logs, process inspection, database snapshot metadata, artifact hashes. No raw secrets or unrelated source data.
- Normal CI never depends on paid providers; real-provider smoke tests are opt-in, budget-capped, and redact captured data before fixture review.
- The deterministic workflow lane covers closed Review output validation, Specifications/Coding return routes, mixed-stage ordering, the three-Review budget, durable finding events, and both confirmed completion choices. Local-completion tests assert that evidence/worktree remain and no remote ref or release attempt exists.

## Test matrix by component

Task 1019 additionally verifies authorization-reference compatibility and
immutability, shared revocation status, model-only edits preserving login,
per-model stage requests despite authentication-probe deduplication, planning
model snapshots, and a prior-schema database copy migrated without changing
existing account data. LiveView tests cover model selection and shared sign-in
controls in both Agents and project settings. Native refresh and years-long
retention cannot be established by fixture tests.
Task 1018 lifecycle coverage also verifies that root impact is aggregated across
linked named agents and current project/board roles, that only a confirmed root
control is rendered, and that scoped provider logout records value-free request/completion events
while propagating authorization-required status. The fake command runner asserts
the app-owned environment and provider logout argv without reading credentials.
Live browser acceptance on 2026-09-20 verifies the real Codex and Cursor command
copy interactions, polite status feedback, and exact 320 px reflow without
horizontal overflow. The viewport override is reset after the check.

| Component | Unit / property | Persistence | Integration | Adversarial | Recovery |
| --- | --- | --- | --- | --- | --- |
| Domain state machines | Transition guards, workflow validation, DAG validation, budget math, retry classification (property-based) | Event/projection atomicity, constraints, idempotent commands | — | Forged completion payloads | Interrupted command replay |
| Leases and dispatcher | Expiry, heartbeat, sleep-gap extension | Partial unique indexes | — | Duplicate dispatch under concurrency | Restart mid-dispatch |
| LocalProcessRunner | Environment allowlist, path canonicalization, port allocation | Environment and process rows | Real processes: process-group kill, timeouts, output bounds | Symlink escape, path traversal, port squatting | Orphan reconciliation after crash |
| Git service | Branch naming, base SHA capture | — | Real worktrees: create, commit, clean status, push to a local bare remote | Dirty base, protected branch, force-push attempt | Worktree drift on resume |
| Power manager | Gap detection math | `power_events` | `caffeinate` lifecycle on a real machine (opt-in) | Wall clock jump without sleep | Wake with dead process, wake with live process |
| Adapters | Event decoding, grant mapping, usage parsing | Session rows, effective grant | Fixture-driven fake CLI; opt-in real CLI | Malformed stream, secret canary in output, injected instructions | Cancel, sleep gap, restart, resume |
| Workflow and Kanban | Scheduling fairness, dependencies | Snapshots | LiveView: keyboard transitions, rejections, reconnect | Invalid transition via UI | Reconnect after gap |
| Knowledge | Front-matter parsing, memory-op classification, redaction | Index/file sync, usage records | Extraction and consolidation with fixture runtime | Secret in evidence, injected publication instruction, cross-project retrieval | Job resume after crash |
| Plugins | Manifest schema, permission narrowing | Registry rows | Detection with fake binaries; conformance per kind | Undeclared access, crashing plugin, output promotion attempt | Plugin restart limits |
| Shell | Token generation, readiness parsing | — | Launch, `/open` exchange, status polling, quit ladder | Token replay, unauthorized browser | Child crash before/after readiness |
| Telemetry | Cost formula, rollups, active vs wall | Samples and rollups | — | Missing samples not interpolated | — |

Claude Code fixture conformance is pinned to `test/fixtures/agent/claude-code-2.1.142.stream.jsonl`. A real smoke is allowed only when the run-scoped authentication probe succeeds; global OAuth alone is not sufficient because bare mode intentionally ignores it.
Codex fixture conformance is pinned to `test/fixtures/agent/codex-0.146.0.jsonl`. Strict config is validated against the installed CLI with an isolated unauthenticated `CODEX_HOME`; a real provider smoke is allowed only after that scoped home's file store authenticates, never by copying the user's global `auth.json` or passing a provider key to the child process. A real 2026-09-21 smoke with the earlier keyring mode failed under an isolated `HOME` despite a successful personal-shell status check. Regression checks now require file-store selection at sign-in, probe, model discovery, launch and logout, and reject symlinked or group-readable credential files. A fresh sign-in and a real isolated provider run remain required.

Saved-agent tests cover persistence, cross-project attachment, immutable copies,
matching login/probe/launch profiles, separate per-run config, role deduplication,
account separation, simulated revocation, stale status updates, unsafe paths and
explicit legacy binding preservation. These checks do not replace authenticated
acceptance: sign in once, attach the account to two projects and start both runs
without another login or copied credentials. Histories may be shared by the
approved ADR-025 contract; permission config must remain independent. Verify
restart, refresh and concurrent use, then revoke and confirm a fresh launch
fails clearly. The 2026-09-20 18:05 UTC real CLI status checks reported sign-in
required; on 2026-09-21 both saved app-owned CLI profiles reported authenticated
after a development-server restart, but Codex's result depended on the personal
shell's Keychain availability and was not a valid isolated-run check. A subsequent
isolated file-store status correctly reports sign-in required. Authenticated
two-project acceptance is still pending. Account-page status alone is not a pass. Old boards/runs have explicit,
audited saved-account linking.
Cursor adapter tests assert run-owned home/config/Claude paths, scoped-auth probing, owner-only generated policy, empty MCP configuration, project-override rejection, launch/resume/cancel behavior, fixture event normalization, redaction, and usage. The retained real-runtime fixture proves its event contract and earlier lifecycle behavior; the current change does not claim a new authenticated real-provider smoke. OpenCode remains a stable-stub test with fail-closed operational callbacks.
The Phase 4 walking-skeleton test uses the fake adapter but real SQLite state, Git repositories, worktree, candidate commit, hibernate/resume lifecycle, evidence files, LiveView confirmation, and local bare push. It asserts a single specification attempt across the sleep simulation, rejects release before approval, rejects candidate path traversal and symlinks, and replays the release command without another push event. A real-provider demo remains opt-in and must use a separately authenticated run-scoped home.

## Fixtures

- Recorded provider output per supported runtime version, redacted, with a compatibility manifest.
- Sample repositories: Elixir, Node, mixed; one with malicious content (prompt injection in README, symlink escapes, protected-path edits).
- Fake agent CLI that emits configurable event streams, delays, crashes, and usage.
- Knowledge fixtures: duplicate facts, contradictory decisions, stale observations, secrets in evidence.
- Plugin fixtures: valid manifests, over-permissive manifests, missing binaries, wrong versions.
- Plugin-kind fakes: one deterministic implementation per closed behaviour;
  the reusable conformance checker validates every operation through a current
  run-scoped capability and the public result boundary.

## End-to-end scenarios

1. Create project → board → task → spec → development → QA → human approval → release handoff → branch pushed to local bare remote and evidence bundle produced.
2. Two boards run concurrently; assert separate worktrees, ports, process groups, and event streams.
3. Pause, hibernate, quit the app, relaunch from the shell, resume; assert single execution of each stage.
4. Simulated sleep gap during development; assert reconciliation events, lease continuity, no duplicate commits.
5. Real sleep drill on a test machine (opt-in): `pmset sleepnow` during a stage.
6. Fail QA and return structured findings to development; assert routing and attempt increments.
7. Lose network or provider auth; assert transient classification, retry within budget, block on exhaustion.
8. Complete a run; extract candidates; consolidate; reject one, accept one, publish one globally; assert files, index, audit, and injected/retrieved/cited usage records in the next run, then accept a correction and assert accepted/contradicted lineage.
9. Enable RTK/XERJ/Ponytail and the read-only MCP plugin with fake binaries;
   assert policy-first wrapping, stage overlay, server-derived namespaces,
   exact package/tool configuration, labeled contributions, and clean
   degradation when binaries disappear. Implemented by the focused reference
   plugin and run-detail tests.
10. Malicious repository: injected instruction to publish knowledge and edit `.cuckoding/`; assert refusal, flags, and approvals.
11. Unauthorized browser access and token replay; assert rejection and audit.
12. Unattended mode overnight simulation: queued approvals, notifications, assertion held only while work is queued.

Scenarios 10 and 11 are implemented by the focused tests documented in
`docs/SECURITY_TEST_MATRIX.md`. Scenario 10 combines the malicious fixture,
command-policy/protected-path checks, and the pending-only knowledge extraction
boundary. Scenario 11 combines loopback/origin/token rejection with secret-free,
append-only security audit rows.

## Quality gates

- Public-message tests scan every LiveView for internal `inspect/1` rendering,
  verify bounded application-owned changeset copy, and exercise representative
  alert/status regions through LiveView tests. The inventory excludes closed
  machine API error codes and non-error state labels.
- Elixir formatting and compilation with warnings treated as errors.
- Unit, integration, and migration tests.
- Static analysis and dependency audit.
- Shell formatting, lints with warnings denied, tests.
- Security fixtures and secret canary scan.
- Accessibility checks and a keyboard-only critical journey (including the lineage graph's table alternative).
- Plugin conformance for every kind with a bundled reference plugin.
- Reproducible release smoke test on a clean machine.

## Determinism

Freeze clock, identifiers, price catalog, workflow version, plugin versions, and provider fixtures where applicable.
