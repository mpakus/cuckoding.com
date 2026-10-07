# Security contract

Cuckoding runs powerful local agents against repository content on the host.
Runtime permissions, owned worktrees and process supervision are required;
they do not provide OS sandbox isolation.

## Boundaries and controls

| Input / boundary | Required control |
| --- | --- |
| Tray → Phoenix → browser | Loopback-only listener, one-time shell bootstrap, single-use short-lived browser handoff, authenticated short-lived sessions, host/origin checks and CSRF |
| Repository/files → planning | Explicit folder scope, canonical paths, symlink/path traversal checks, bounded reads, content treated as untrusted evidence |
| Agent output → commands | Closed bounded schema, role/battle/revision binding, allowlisted actions, grants and idempotency checked host-side |
| Worker → host | Runtime grant mapping, recorded enforced/unenforced restrictions, clean child environment, process-group ownership and cancellation |
| Parallel work → Git | Separate worktrees, dependency checks, task leases, reviewed candidates and serialized compare-and-swap integration |
| Secutor → completion | Independent session, exact spec/head/check evidence; Summa Rudis cannot override failure |
| Logs/artifacts → UI/disk | Redaction before persistence/broadcast, public summaries only, escaping and authorized artifact IDs |
| Settings/files → authority | Immutable trusted snapshot; changed execution policy is never adopted silently within a battle |
| Update → application/data | Verified signature/provenance, backup first, tested migration/restore; no destructive downgrade |

Do not expose the real home directory, SSH keys, personal Keychain, cloud
credentials, unrelated repositories or personal provider history through app
configuration or MCP. Host executable discovery is metadata-only and grants no
filesystem access to a worker. Do not print raw process argv or environments.

## Authorization and secrets

Provider runtimes own their authentication and refresh. Cuckoding initiates scoped
login/status operations using a dedicated app-owned provider profile and stores
only non-secret references/status. It never reads, copies or injects provider
token values into prompts, configuration, events, argv or environment variables.
A provider may read its own credential store; this is a residual host-process
risk, not a claim that no credential exists anywhere in that process.

Saved roles may share one authorization while keeping instructions, sessions,
worktrees and evidence separate. Explain provider-profile/history sharing and
offer separate sign-in profiles. No silent import of personal CLI credentials or
config. If a runtime cannot satisfy this boundary, mark it unsupported until a
reviewed adapter solution exists.

Use the host secret-store boundary for application secrets. Any future approved
push/PR service owns its own narrowly scoped credentials; agents never receive
them. Do not log authentication URLs with secrets, cookies, headers or token
values. Redaction must handle split chunks and nested payloads; malformed or
oversized protocol data is rejected before storage.

## Authority

Start battle authorizes routine local work, required role sessions, approved
checks, bounded recovery and integration into the app-owned battle branch.
It does not authorize push/PR, merging the user's branch, deployment, arbitrary
network or filesystem expansion, new tools, global knowledge publication or
destructive cleanup.

Git initialization requires its own explicit confirmation, as requested by the
user. Initial-commit file selection is previewed. Role names and instructions
cannot grant capabilities. Custom roles default to planning/read-only; changing
a grant or schedule is confirmed and audited. Repository changes to
`.cuckoding/` and other protected execution configuration can be proposed but
cannot become active policy in the same battle without a new explicit decision.

No routine human approval is inserted between authorized task stages. Ask only
for unresolved intent, exhausted limits or a genuine trust boundary. Clarification
answers cannot silently enlarge the original authorization.

## Recovery and audit

Persist intent before effects and events before broadcast. Inspect executable,
PID/start identity, working directory, protocol owner and listeners before any
adoption/signal/retry. Unknown ownership closes admission. Never signal unrelated
provider applications or remove dirty/ambiguous worktrees. Preserve failed
branches, logs and DB snapshots for review.

Record authorization changes, grants, start snapshots, accepted/rejected
decisions, transitions, review results, approvals, process lifecycle, integration,
sleep/wake, recovery, settings changes and cleanup. Keep hidden chain-of-thought
out of every artifact and UI. Public reasoning summaries and tool activity are
sufficient.

[Testing](TESTING.md) requires malicious-repository/proposal fixtures, token replay,
cross-Arena access refusal, canaries, process identity reuse, Git drift,
concurrent integration and recovery checks. A provider fixture does not establish
safe real-provider behavior. A secret leak or ambiguous authority is a stop
condition, not an automatic retry.

## R010 implementation and static-analysis exceptions

The native shell writes a 0600 launch file in the private rebuild root. Startup
consumes/deletes it; a one-use bootstrap establishes in-memory shell authority.
The browser gets a single-use 60-second handoff and an encrypted HttpOnly,
SameSite=Strict cookie backed by a hashed, expiring 30-minute DB session.
LiveView checks authority on mount, events, incoming updates and expiry. Restart
rotates the cookie key. Authentication routes do not log request parameters.

HTTP and WebSocket origins must match localhost/127.0.0.1 and the current
ephemeral loopback port. HTTP also rejects foreign Host and cross-site fetches;
LiveView retains its CSRF token check. CSP permits only local assets/connections,
with no framing, objects or inline scripts. The shell sends a heartbeat every
five seconds; loss of authority/service closes the shell, and the service exits
after 30 seconds without shell contact. Sleep reconciliation remains R060.

Sobelow exclusions are limited to intentional loopback HTTP (`Config.HTTPS`),
its inability to resolve the dynamic-port origin MFA (`Config.CSWH`), the browser
pipeline whose CSP is already set by `Boundary`, and two storage functions with
explicit absolute-path/symlink/private-file guards. Other checks fail at low
confidence or higher. Boundary, replay, expiry and storage tests cover these
decisions; exclusions are not permission to weaken them in later slices.

The host is not an adversarial same-user sandbox: another process with the
user's filesystem rights can inspect app-owned data. No provider credentials,
agent grants, external publication or remote listener exist in R010.
