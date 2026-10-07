# Security contract

R040a Arena registration is metadata-only and grants no agent access. The native
directory chooser runs as the app-owned fixed helper with a cleared environment,
private HOME, owned process group, no child processes and a two-minute deadline;
stdin closure/cancel terminates its window. Results are bounded to 8 KiB and
closed status/path fields, then revalidated by Elixir. Canonical paths must have
directory-only, non-symlink components; root/home ancestors, system roots,
known credential directories and overlapping application storage are refused.
Device/inode identity is checked again in the registration transaction. A `.git`
entry is only statted without following it or reading its target. Registration
neither validates Git nor protects against later filesystem changes; execution
must revalidate the folder and apply separately authorized grants. Events omit
project names, paths and content; local Arena/selection records contain the
explicitly selected path. No model/provider is involved.

R040c Git inspection is separately requested. Initialization needs fresh,
observation-bound confirmation and exclusive creation of the missing `.git`.
The helper pins and verifies the registered directory handle, locks it against
other Cuckoding Git helpers, and uses only fixed `/usr/bin/git` builtins. It clears
inherited Git variables/config, disables credentials, hooks, fsmonitor, replacement
objects, lazy fetch and protocols, and supplies an empty init template. Repository
config keys are inspected without includes before opening the repository. Nested
roots, gitfiles, linked metadata, symlinks, hardlinks, alternate object stores,
includes, worktree overrides and extensions are refused. Metadata walks stop at
50,000 entries; config is at most 64 KiB and command output at most 8 KiB. No
working-file content, index status, commit author or raw diagnostics are exposed.

The native operation has a 15-second deadline and owned child process groups;
stdin loss/cancel kills descendants before reaping their leader. The Port waits
20 seconds and reports unacknowledged/nonzero cleanup as uncertain. Interrupted
claims never replay. Cancellation may leave a newly created/partial `.git`; retain
it and re-inspect, never delete it as rollback. An advisory directory lock cannot
exclude ordinary Git or hostile same-user filesystem changes. Validation narrows
but cannot eliminate metadata races or forcibly killed-helper cleanup risk; these
are supervised host operations, not an OS sandbox.

R040d initial commits require a fresh exact preview and separate confirmation.
Only repositories with no refs and no index are accepted. Selection is explicit:
at most 16 regular single-link files, 240-byte relative paths, 1 MiB per file,
8 MiB total and 7,000 bytes of serialized preview metadata. Traversal, symlink
components, special files and common credential paths are refused. This filename
guard is not content-level secret detection; the user selects appropriate files.
Reads use pinned directory handles and no-follow opens. Persist SHA-256/size/mode,
not content. Recheck bytes, branch, config and directory identity before publishing.

Git plumbing writes raw approved bytes with no filters, hooks or signing, using
a private candidate index and fixed Cuckoding author/message. Explicit selection
can include ignored files. Exclusive index/HEAD locks cover preparation; packed-ref
and branch locks guard exclusive publication of the absent loose branch. No existing
index/ref is overwritten. The first commit has no parent and no Git reflog is
created; SQLite retains consent and receipt. Working files remain unchanged.
Index and ref publication are not atomic: cancellation/failure may leave objects,
a candidate index, a staged index or a completed commit without a receipt. Retain
all effects, re-inspect and handle existing staging manually; never replay or
remove ambiguous files/locks automatically. Hostile same-user metadata changes
remain outside isolation guarantees. No agent, push, network or later commit is authorized.

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
LiveView checks authority on mount, events, incoming updates and expiry. Stateful
LiveComponents install the same DB-backed event guard explicitly; parent event
hooks do not cover component-targeted messages. Expired sessions cannot adopt
teams, read selected documents, launch/cancel planning or import proposals. Restart
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

## R020 inspection and authorization boundary

The bundled helper exposes fixed inspection/login/logout operations, not a
caller-selected RPC method. Inspection validates private profile paths/metadata, forces
file-based provider credential storage, checks effective profile/provider config,
and sends only initialize, config/read, account/read and model/list. It never
starts a thread, turn, tool or host command. Provider requests or account
changes during inspection abort. No raw frames, account email/plan, auth URLs or
provider error text enter Cuckoding logs/SQLite. Codex may maintain its own
private runtime files inside the profile. Cuckoding does not read credential values.

Separately confirmed login/logout add only the managed account RPCs. Provider
URLs are bounded, parsed against an exact official HTTPS host/path allowlist twice,
kept in expiring dispatcher memory and exposed through a session-protected local
redirect with no-referrer/no-store headers. The LiveView process keeps only a
readiness flag and command ID. Neither URL nor login ID enters SQLite or logs.
A matching completion and fresh account read are required before publishing model
observations. Native locking prevents concurrent profile helpers. Cancellation
retains the durable claim until helper exit or a reported cleanup timeout;
cancelled/interrupted operations leave authorization unknown and require explicit
reconciliation. This cannot reverse
a provider-side success racing with cancellation. Authentication is never replayed.

All child environment values are explicit; stdin loss, cancellation and deadlines
stop the owned process group. Same-user TOCTOU, force-killed helper reconciliation,
managed policy compatibility and physical sleep still require later acceptance.
Account status is an observation, not proof of token validity or model access.
Catalog fixtures do not satisfy the real-provider authorization gate.

R020d's separate model diagnostic records explicit usage consent and a fresh
executable/account/catalog snapshot. Its fixed ephemeral thread must report the
requested model and validated permission profile before inference. The named
profile denies filesystem root, allows read access only to an empty app scratch
directory and disables command network access; inherited project instructions,
MCP, tool-bearing features, hooks and permission expansion are disabled/checked.
Provider inference itself necessarily uses the provider connection. A runtime
that cannot report these restrictions is refused; this does not make the host
runner an OS sandbox. Real grant-adversarial execution remains an acceptance gate.
Model output cannot become a command: only matching completion and the fixed
acknowledgement can pass. All other content is discarded, including hidden
reasoning. Cancellation/interruptions cannot persist a late pass or replay usage.

R040e brief planning reuses that same restrictive grant, private profile lock,
clean child environment, owned process groups and 120-second turn limit. It adds
one fixed `outputSchema` turn, not arbitrary RPC access. Brief and saved role
instructions are untrusted user-message data, sent over a bounded stdin request
(64 KiB), never process arguments. Optional selected document snapshots are
untrusted task data; no Arena root path, tool, policy or permission definition
becomes runtime authority. Provider inference uses the
provider connection only; runtime tools/network remain disabled.

The host binds consent to board/team/executable/connection/model observations and
validates output structure, text/collection bounds, unique titles and matching
request/model/effort/thread/turn/grant receipts before persistence. Only known
public fields survive; invalid results discard proposal text. HEEx escapes all
rendered text. Proposals cannot grant access or execute actions; a separate scoped
import creates a draft in Specs once. User-supplied brief/instructions and public
proposal text are retained locally and sent to the selected provider with consent;
this is not a general-purpose secret scanner. Fixtures prove protocol handling,
not real-provider compliance with the grant.


## Selected planning documents (R040f)

A local preview command authorizes only the entered Arena-relative `.md`/`.txt`
paths: 1–4 unique files, 240-byte paths, 4,096 UTF-8 bytes each, 12,000 total.
Native reads reuse the pinned Arena directory identity and exclusive helper lock,
`openat` with no-follow/nonblocking descriptors, regular-file/single-link checks,
bounded reads and before/after metadata checks. Root opens require a directory.
Traversal, absolute paths, credential-like path components, symlink parents/files,
hardlinks, special files, invalid UTF-8 and controls except tab/CR/LF are refused.
Git is not invoked; Git metadata does not influence these reads. A changed root or
file refuses the preview rather than returning partial content.

The native receipt is bounded to 32 KiB and independently validates content,
byte counts, SHA-256, selected order and scope in Elixir. Exact text is retained
locally, rendered through escaped HEEx, and only sent to the provider by a second
explicit planning consent bound to a fresh scoped snapshot. Changed selection,
team or connection clears consent. Expiry/cancellation cannot accept a late result.
Source text travels over stdin, never argv/events/diagnostic logs; provider input
is validated again natively and retains the existing scratch-only permissions.

Snapshots describe bytes read at preview time, not live file state at inference.
Known credential paths are excluded, but arbitrary text may contain private data;
this is not a secret scanner. Users review the exact selected text before sending.
Same-user filesystem interference and the provider's actual enforcement remain
outside fixture proof; real-provider acceptance is still required.

R040h reference arrays grant no new authority. A new v2 response may reference
only earlier suggestions and document snapshots in its frozen request; the host
rejects contract downgrade and malformed/foreign references before storing text.
Import resolves same-board prerequisite UUIDs through application receipts, never
provider-supplied task IDs. Paths/hashes/text come from the retained selected
snapshots; this validates provenance scope, not the truth of a model's citation.
Original-source disclosures remain session/scoped and escaped after draft edits.
