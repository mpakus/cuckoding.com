# Security Test Matrix

This matrix ties every trusted-host risk in `docs/TRUSTED_HOST_THREAT_MODEL.md`
to executable regression evidence. The focused paths are part of the normal
`rtk mix quality` run; release, packaging, and physical sleep evidence remain
separate gates where noted.

| Risk | Executable coverage | Residual gate |
| --- | --- | --- |
| R1 repository prompt injection | `test/cuckoding/execution/command_policy_test.exs` rejects undeclared commands from the malicious fixture and requires exact protected-path approval; `test/cuckoding/adapters/agent_adapter_test.exs` records enforced and unenforced grants | An unrestricted host subprocess can read anything available to the macOS user |
| R2 credential theft | `test/cuckoding/security_test.exs`, adapter canary tests, `test/cuckoding/execution/local_process_runner_test.exs`, and `test/cuckoding/diagnostics_test.exs` cover opaque references, stdin-only Keychain writes, environment refusal, and pre-boundary redaction | Provider CLIs own their credentials outside Cuckoding |
| R3 local browser access | `test/cuckoding/shell_auth_test.exs`, `test/cuckoding_web/shell_controller_test.exs`, and `test/cuckoding/security_test.exs` cover loopback/origin rejection, single-use tokens, replay, secret-free durable audit, and append-only evidence | A compromised macOS account remains trusted-host compromise |
| R4 plugin permission escape | `test/cuckoding/plugins/manifest_test.exs`, `registry_test.exs`, and `contracts_test.exs` reject over-permissive manifests, permission expansion, tampered capabilities, private output, and output promotion | Enforcement beyond declared grants depends on the selected runner |
| R5 policy self-escalation | `test/cuckoding/execution/command_policy_test.exs` freezes the trusted hash, flags `.cuckoding/`, and scopes approval to the exact changed path digest | A human can explicitly approve a malicious change |
| R6 destructive Git or unreviewed push | `test/cuckoding/execution/git_service_test.exs` and `test/cuckoding/walking_skeleton_test.exs` cover confinement, protected branches, candidate ownership, host-only credentials, explicit approval, and idempotent non-force push | Credentials independently available to the macOS user remain outside Cuckoding |
| R7 resource exhaustion | `test/cuckoding/execution/scheduler_test.exs`, `test/cuckoding/telemetry/resource_metrics_test.exs`, and `accounting_test.exs` cover admission, concurrency, memory/port signals, measured limits, budgets, and cost labels | Host CPU/memory limits and provider accounting can remain advisory or delayed |
| R8 poisoned or cross-project knowledge | Knowledge extractor, publication, store, injection, and retrieval-controller tests cover redaction, pending review, global approval, capability scope, correction, revocation, and cross-project refusal | A reviewer can accept plausible poisoned content |
| R9 duplicate work after sleep/crash | Lifecycle, command, reconciler, power-manager, and walking-skeleton tests cover idempotent commands, lease extension, append-before-broadcast, and single stage/push execution; Task 1002 adds five-stage sleep and battery-clamshell evidence | External provider CLIs still own their native session-resume behavior |
| R10 PID reuse | `test/cuckoding/execution/local_process_runner_test.exs` and `reconciler_test.exs` refuse mismatched start identity and unavailable inspection | Platform metadata can become unavailable, which blocks rather than guesses |
| R11 path escape | Git-service, command-policy, lifecycle, adapter, knowledge-store, diagnostics, and update-snapshot tests cover traversal, canonical roots, regular-file checks, and symlink rejection | An arbitrary provider subprocess is not an OS sandbox; same-user races remain possible |
| R12 cross-run artifact/private output leak | Agent Floor tests prove run-owned artifact metadata omits backing paths; knowledge store/injection/controller tests enforce project and run capability scope | User-approved exports are outside later Cuckoding control |
| R13 malicious/destructive update | Release, update, snapshot, shell-controller, Rust updater, and packaged rollback checks cover pinned signatures, snapshots, migration guards, authenticated transitions, and rollback | Signing-account compromise requires incident response and Task 1004 release evidence |
| R14 analytics disclosure | Activity, configuration, security-canary, and diagnostics tests prove bounded local allowlists and redaction; the MVP has no external analytics sender | Any future third-party crash or analytics service requires a new consent and processing review |

## E2E scenario 10

`test/fixtures/malicious_repository/README.md` requests SSH reads, same-run
policy escalation, and unapproved global publication. The command-policy test
proves the text cannot select an undeclared command, the protected-path test
flags `.cuckoding/` and requires a digest-scoped approval, and the knowledge
extractor test proves injected text can create only a pending project candidate
that cannot request global publication before human acceptance.

## E2E scenario 11

The shell controller test rejects non-loopback hosts, cross-origin requests,
missing/invalid credentials, bootstrap replay, and browser-token replay. It
also asserts durable rejection rows by closed event type and proves bootstrap,
shell, and browser tokens are absent. The security test independently proves
the rows are append-only and reject query-bearing or unknown audit input.

## Focused command

```sh
rtk mix test test/cuckoding/security_test.exs test/cuckoding_web/shell_controller_test.exs test/cuckoding/execution/command_policy_test.exs test/cuckoding/adapters/agent_adapter_test.exs test/cuckoding/execution/local_process_runner_test.exs test/cuckoding/execution/git_service_test.exs test/cuckoding/execution/scheduler_test.exs test/cuckoding/plugins/manifest_test.exs test/cuckoding/plugins/registry_test.exs test/cuckoding/plugins/contracts_test.exs test/cuckoding/knowledge/store_test.exs test/cuckoding/knowledge/extractor_test.exs test/cuckoding/knowledge/publication_service_test.exs test/cuckoding/knowledge/injection_test.exs test/cuckoding_web/knowledge_retrieval_controller_test.exs test/cuckoding/updates_test.exs test/cuckoding/updates/snapshot_test.exs test/cuckoding/diagnostics_test.exs
```
