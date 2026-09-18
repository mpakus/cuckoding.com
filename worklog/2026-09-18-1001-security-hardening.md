# Worklog — 1001 capability, secret, and plugin hardening

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 1001
- Status: complete
- Human/agent owner: codex
- Branch: `feature/1001-security-hardening`
- Start revision: `fb750ae`
- End revision: recorded by the Task 1001 commit

## Acceptance criteria

- Map every threat in `docs/SECURITY.md` to executable coverage or an explicit
  residual-risk drill.
- Pass the malicious-repository and unauthorized-access/token-replay E2E
  scenarios from `docs/TESTING.md`.
- Verify capability narrowing, effective-grant audit, secret canaries, plugin
  undeclared-access refusal, and cross-project knowledge isolation.
- Document the host runner's non-sandbox limitations in the product UI and
  security documentation.

## Reference coding

- Focused project, Vibe Kanban, and Hydra XERJ searches were attempted before
  implementation. The documented loopback node was unreachable, so indexed
  retrieval was degraded and the pinned checkouts were inspected directly.
- Pinned Apache-2.0 Vibe Kanban revision
  `735654971bd396aa97b65166955678e4c34f8bf8` uses a closed audit action and
  structured HTTP method/path/status at `crates/remote/src/audit/mod.rs:4-130`,
  including rejected-session audit at
  `crates/remote/src/auth/middleware.rs:131-143`. Cuckoding adapts only that
  bounded shape and strengthens it with append-only SQLite durability while
  excluding query strings, tokens, headers, hosts, origins, IPs, descriptions,
  and remote-account identifiers.
- Ponytail 4.10.0 (MIT) full mode selected the existing redactor, policy,
  plugin-capability, knowledge-review, and LiveView paths instead of new
  frameworks or dependencies.

## Work performed

- Added an append-only `security_audit_events` table and a closed writer for
  rejected authorization, browser-token replay, and loopback-boundary events.
- Audited the shell/controller path without storing authorization headers,
  tokens, query strings, origins, hosts, IP addresses, or arbitrary text.
- Expanded the malicious repository fixture with explicit SSH-read, same-run
  policy escalation, and unapproved publication instructions. Tests prove the
  content cannot select an undeclared command, protected `.cuckoding/` changes
  remain approval-gated, and extraction yields only a pending project candidate.
- Added plugin-capability permission-tampering refusal and retained existing
  capability narrowing, effective-grant audit, secret canary, and cross-project
  knowledge tests in the focused security matrix.
- Added one reusable accessible host-runner warning to task, run, and agent
  pages so the non-sandbox boundary is visible before and during execution.
- Added `docs/SECURITY_TEST_MATRIX.md`, mapping R1–R14 to executable evidence
  and honest residual gates, and synchronized security, testing, UI, database,
  plan, and task documentation.

## Verification

- Focused threat/UI matrix (`rtk mix test` with the paths recorded in
  `docs/SECURITY_TEST_MATRIX.md` plus policy, board, and Agent Floor LiveView
  tests) — 85 tests, 0 failures.
- `rtk mix quality` — 10 properties and 202 tests passed; formatter/compiler,
  Credo, Sobelow, and Hex audit passed with no findings. The first full run
  found one alias-order issue after tests passed; it was fixed before this
  clean run.
- `rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/ruby desktop/release_metadata_test.rb`
  — 6 runs, 15 assertions, 0 failures.
- `rtk proxy sh desktop/build.sh` — production release and Tauri app built;
  9 Rust tests and clippy passed; the sterile verifier proved the new migration,
  six credential-free rejection rows including browser replay, normal and safe
  startup, diagnostics canaries, graceful/crash cleanup, and update rollback.
- `rtk git diff --check` — passed.
- RTK proxy exceptions were limited to exact build/release streams and the
  repository's sterile-environment checks, where filtering changes semantics.

## Handoff

Complete. Residual risks remain explicit: the host runner is not an OS sandbox,
provider CLIs own their credentials and resume behavior, plugin enforcement
depends on the selected runner, same-user path races remain possible, reviewers
can accept poisoned content, and signing-account compromise requires incident
response. Real sleep/crash drills continue in Task 1002.
