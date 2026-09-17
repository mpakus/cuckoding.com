# Worklog — 0204 Keychain SecretStore and redaction

## Metadata

- Date/time (UTC): 2026-09-17T20:57:55Z
- Task: 0204
- Status: done
- Human/agent owner: Codex
- Branch: `feature/0204-secret-store-redaction`
- Start revision: `75f8e0d`
- End revision: task commit
- Environment: Apple Silicon macOS 27.0, Erlang/OTP 28.4, Elixir/Mix 1.19.5

## Intended outcome

Store only opaque secret references in Cuckoding, keep raw values in macOS Keychain behind a replaceable behaviour, audit every reference use without recording the value, and provide one recursive redaction boundary for logs, events, artifacts, exports, broadcasts, and knowledge inputs.

## Acceptance criteria restated

- Raw secrets, authorization headers, full environment maps, and secret-bearing arguments never reach persistence or broadcast fixtures.
- Every successful secret-reference read writes an audit record containing only reference metadata.
- Keychain commands pass values through stdin, never argv, and use an injected command runner in tests.
- Canary values are removed from nested strings, maps, lists, event payloads, export data, UI/broadcast data, and knowledge inputs.

## Context inspected

- Required product, architecture, database, workflow, security, and execution-environment documents.
- Task 0204 and merged Phase 2 foundation through `75f8e0d`.
- Mandatory Ponytail full, security-review, Elixir/Phoenix/LiveView, and quality-gates skills.

## Work performed

- Added the `SecretStore` behaviour/facade, macOS Keychain adapter, injected command runner, and deterministic fake store.
- Added opaque UUIDv7 Keychain references and value-free reference-use audits with purpose, optional run, and timestamp.
- Added a recursive redactor for strings and nested containers; authorization, cookie, credential, token, complete environment, and argv fields are removed wholesale.
- Added canaries covering database events, simulated UI broadcast, artifacts, exports, knowledge input, nested headers, environment maps, and argv.
- Documented the absolute CLI/stdin boundary and the future Security.framework adapter path.

## Artifacts

- Commits/patches: task commit
- Migrations: `20260917210000_create_secret_access_audits.exs`
- Logs/reports/screenshots: this worklog
- Configuration or policy hashes: unchanged

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk mix test test/cuckoding/security_test.exs` | pass | 3 tests, 0 failures; opaque references, audit, stdin-only Keychain commands, and cross-boundary canaries passed. |
| `rtk mix quality` | pass | 8 properties and 42 tests, 0 failures; warnings-as-errors compile, strict Credo, Sobelow, and dependency audit passed. |
| Clean and production migrations | pass | The disposable database rebuilt through all migrations; the retained production copy applied only the secret-audit migration and assembled the release. |
| XERJ current-project refresh | pass | Current generation committed after the documentation freeze with every code file indexed. |

## Decisions and deviations

- Ponytail full used `/usr/bin/security`, stdin, one behaviour, one audit table, and one recursive redactor; no vault, encryption dependency, or agent secret-injection path was added.
- XERJ returned Vibe Kanban's `SecretString` and redacted debug formatter at `crates/relay-tunnel/src/server_bin/auth.rs:14-15,58-68` in pinned revision `735654971bd396aa97b65166955678e4c34f8bf8` (Apache-2.0). Cuckoding adds Keychain references, access audit, stdin-only writes, and recursive boundary redaction.

## Risks and blockers

- The real Keychain smoke requires an explicit disposable credential and user authorization; this task verifies the exact CLI boundary through an injected runner without mutating the user's Keychain.
- Later output-producing services must call the shared redactor before their persistence or broadcast adapter; task 1001 provides adversarial end-to-end enforcement across the completed product.

## Handoff

Phase 2 is complete. Proceed to task 0301 for confined Git worktree lifecycle.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
