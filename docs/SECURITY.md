# Security contract

R102 locks Bandit 1.13.1 with Thousand Island 1.6.0. The upstream fixes cover
[unvalidated HTTP/1 request authority](https://github.com/mtrudel/bandit/security/advisories/GHSA-v53v-9hvg-37jf)
and [HTTP/2 send-window deadline resets](https://github.com/mtrudel/bandit/security/advisories/GHSA-69m6-wcv4-rwcf);
1.13.1 also preserves Phoenix parser-error rendering. Current Hex advisories and
the existing audit both gate quality; no advisory ignore or runtime permission is
added. Local raw-socket tests cover authority/origin refusal and parser errors;
HTTP/2 resource-exhaustion attacks were not exercised. See
[evidence](../worklog/2026-10-21-R102-bandit-security.md).

## R050e Start and check grants

Start grants bounded local completion for frozen Codex roles/tasks/checks. Provider sessions retain host-only file tools and cannot run commands. The check runner uses a fresh empty Codex profile and private candidate clone, network denial, protected policy paths, bounded output hashing and frozen argv/executable identities. Its initial single-process grant forbids forks and tracks the inner session leader by PID/start identity; cleanup uncertainty is retained instead of claiming Stop. Toolchain/subprocess checks are unsupported. Native battle branch creation and candidate integration are exclusive, audited and compare-and-swap; no source checkout change or remote operation is authorized.

R050f removes mandatory command configuration, not verification or execution
boundaries. Only a new `arena-loop-v2` empty command scope skips command stages;
independent reviews remain mandatory. Generated verification prose cannot launch
commands. No host command evidence is invented, and Secutor must block missing
required runtime/test evidence. Existing declared commands and v1 snapshots retain
their exact gates. No provider, filesystem or process grant is broadened.

R020m's optional `check_codex_isolation` uses fixed commands and a fresh empty
profile to test two disposable folders with the observed Codex
`0.162.0-alpha.17.2`. It touches no Arena or signed-in profile and uses no model.
It tests read-only/writing, sibling/private fixtures, protected `.git`/`.cuckoding`,
symbolic/hard links, protected-directory rename and loopback network denial.
The local endpoint is proven reachable outside the sandbox and dropped before
the receipt. Explicit `:tmpdir`/`:slash_tmp` denial is required: minimal system
access alone allowed sibling reads/writes in the initial experiment.
This fixture result is not a universal filesystem or model-tool permission proof.

The diagnostic clears inherited environment, owns child process groups, caps
each stdout at 128 bytes, drops stderr, and has a 20-second monotonic/wall deadline.
Only normalized result/contract/version, bounded child PID/start observations and
elapsed time reach SQLite. Commands bind the exact connection/version/executable;
expired/cancelled work cannot publish success and interrupted checks never replay.
Fixtures/partial effects remain in private per-command probe directories.
Historical success never grants repository execution; future task admission still
needs effective grants and protected-policy validation for its actual layout.

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

## Simple Arena authority (D022)

Creating the default board during registration adds SQLite records only; directory
identity, session, confirmation and idempotency checks remain. Moving setup into
Advanced does not change its consent or grant semantics. R050e Start separately
records bounded battle authority; opening the Arena or inspecting a preview
never executes work.

Target Create tasks authorizes bounded local source collection and disclosed
provider use, not execution. Before replacing explicit selected files, implement
finite versioned depth/count/byte/type limits, root identity and pinned descriptor
checks. Prefer `docs/`, then relevant eligible project files; exclude known secret
paths, `.git`, binaries, vendor/build outputs, links and escapes. Record skipped
and truncated scope and permit inspection before broader selection. Do not claim
filename filters detect every secret; explain that selected source text is sent.
Provider prompts get frozen untrusted text, never a live Arena path grant. Reject
instructions inside files that ask for more access or changed policy.

Start separately freezes execution authority, current snapshots, checks and limits.
Its normal worktree/spec preparation must not introduce per-task human ceremonies.
Git init and first commit still need their exact contextual consent, and protected
configuration/new access/publication still require a separate decision. Planning
works without Git. R040l now implements the bounded folder reader described below;
the narrower R040f manual-selection bounds remain unchanged.

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

R060g adds only fixed read-only retained integration inspection. New Start
snapshots opt into `retained-integration-v1`; startup binds the pending read to
the exact interrupted integration, after settled earlier stages. Native code
requires existing exact intent/publication/receipt under the repository lock,
rechecks source identity, app ref, candidate ancestry and owned worktree bytes,
and never repairs or replays publication. Failed reads prove no cleanup. The
domain retains the interrupted attempt and records the bound observation
transactionally before pausing; original deadlines and explicit Resume still
gate continuation. Historical grants, interrupted Stop, missing receipts,
provider-store/process recovery, sleep and cross-provider acceptance remain open.

R060h narrows new battle authority after a timing discontinuity; it adds no host
permission. The independently supervised guard records only bounded UTC and
monotonic deltas, never process death or inferred sleep duration. Admission and
worker settlement check it; helper active polling uses existing cancellation
and owned cleanup. Effects can occur before polling observes a gap; retain those
effects and reject the stage result without advancing state. A recorded bound
cleanup receipt may permit Stop only. Guard failure stops workers with its
execution group before resetting the clock baseline; unfinished native effects
retain inspection gates. Historical grants, deadlines, independent review and
exact connection bindings are unchanged. Physical sleep/wake,
lease reconciliation and active-time accounting remain unverified/unimplemented.

R060i adds only the fixed idle-system sleep capability for new Start snapshots.
Phoenix computes eligibility from SQLite and original deadlines; browser/provider
text cannot request native power actions. The authenticated `/shell/status`
returns `shell-lease-v1`, a boolean and the fixed 15-second lease. The shell
validates this closed lease object before creating one PreventUserIdleSystemSleep
assertion with explicit OS timeout TurnOff. Timeout never releases/reuses its ID;
owned release precedes renewal, and release failure cannot accumulate assertions.
Idle/pause/quit/transport/protocol failure/drop release it; kernel/OS failure is
reported as unavailable without making the app unusable. Forced sleep, display
sleep, lid closure and low battery remain possible.

Only the bearer-authenticated shell may report the fixed held/released/unavailable
states through `X-CC-Power-State`; invalid values are rejected before observation.
Audit state changes, not every heartbeat. Reports contain no OS error text,
project paths, agent payloads, process lists or credentials. Settings shows the
transient last report with timestamp/age and marks it stale after 15 seconds on
either UTC or monotonic time, or backward time;
restart returns Unknown. This is neither execution/cleanup evidence nor a claim
of current guaranteed protection. Source-dev heartbeats do not fabricate reports.

R060k native closure pins the unreaped leader through final signalling, bounds
waits and observes owned-group disappearance before publishing success. A cached
result prevents repeat signals; missing leader ownership refuses cleanup. All
provider normalizers preserve explicit false/malformed cleanup as a refusal,
including cancellation with a zero helper exit. Public host effects remain
retained, but no successful report/account observation is accepted. Uncertain
Cursor stores remain private and are not deleted as purported cleanup. This
cannot detect escaped groups, prove hard-killed session closure or recover absent
receipts; historical absent fields gain no new recovery authority.

R060l writes only native public closure metadata under a new frozen policy.
The exclusive intent binds the exact request digest/connection/provider/runtime
and canonical private UUID scratch before launch. Intent/closure files live in
`provider-closures/<UUID>`, outside the provider grant; scratch remains empty.
The final file is
created only after explicit verified closure, including Cursor store removal.
The fixed inspection entrypoint reads bounded single-link regular files through
pinned directory/file descriptors, refuses links/foreign bindings/partial files,
and launches or signals nothing. Executable replacement or account changes cannot
turn this historical read into a new provider launch. SQLite appends the verified
observation and clears its pending marker atomically, never rewriting the original
interrupted attempt. Only Stop and exact-connection capacity may consume it;
settled/Resume/Retry/Skip predicates stay unchanged. No receipt/report is invented,
no edit/store is erased and no missing process is treated as cleanup evidence.

R060f worker completion uses the existing claim/result validators inside the
transaction, then sends only a completion signal to its coordinator. Unexpected
worker execution/settlement exceptions terminate with a fixed reason before OTP
Task logging can print provider/database payloads. Monitors retain interruption
without inferred cleanup; terminal receipts cannot be overwritten. Invalid or
foreign results cannot establish cleanup through a bare boolean. Stop races use
only an exact, fully validated stage receipt and never accept its work.

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
pipeline whose CSP is already set by `Boundary`, and storage helpers with
explicit absolute-path/symlink/private-file guards. Other checks fail at low
confidence or higher. Boundary, replay, expiry and storage tests cover these
decisions; exclusions are not permission to weaken them in later slices.

The host is not an adversarial same-user sandbox: another process with the
user's filesystem rights can inspect app-owned data. No provider credentials,
agent grants, external publication or remote listener exist in R010.

## Source-development tools (R011)

`bin/dev.server` explicitly launches `MIX_ENV=dev` with an allowlisted environment,
private HOME and `.ccoding/ui-dev/` database/profiles. It reuses installed Mix
archives as executable build tools, not personal Mix/Hex configuration. The normal
bootstrap, one-use browser handoff, session checks and shell heartbeat remain in
place. A cooperative data lock prevents a second source server on this root.

Tidewave and its unauthenticated developer MCP/toolbar were removed in R011b.
The application CSP retains local assets/connections, no eval/inline scripts and
no framing. Only Phoenix's development reload iframe permits its inline script
and same-origin framing; production/test compile out that route. The private
launcher environment is not a sandbox against host filesystem access. Historical
private recordings under `tmp/tidewave/` stay ignored, along with developer data;
removal does not erase user artifacts or change global client settings.

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

R020h's wizard buttons explicitly authorize one named version/profile operation;
server-owned form keys and setup revisions reject stale submissions. Model usage
still has separate consent. Saving model choices only writes public metadata and
cannot grant execution or silently replace existing role bindings. The restricted
turn parser tolerates bounded `warning` and `deprecationNotice` notifications without
storing their text. The transport still refuses server requests and account drift;
tool activity, model substitution and foreign completions remain failures.

R080a separates catalog age from connection invalidation. Saved planning/task
bindings may reuse an aged successful catalog only with the same recorded
executable, account observation, model ID/runtime model and reasoning effort.
Missing/malformed/future timestamps, failed lookups and invalidated profiles still
refuse use. New selections and diagnostics retain the 24-hour gate. Native
account/model/config validation remains required before dispatch; age relaxation
does not grant provider usage, replace an account/model or authorize execution.

Confirmed logout atomically clears the connection's current default/Arena/board
role bindings through new immutable revisions and adoption events. Historic teams,
commands and battle snapshots remain unchanged. Exact-connection unfinished battle
use, busy profile/planning work and stale/session-invalid forms refuse the action
before unassignment. Roles remain unassigned if native logout fails; reconnecting
does not silently restore them. No credential values are read or copied.

R080b does not require executing a missing/changed/unverified program merely to
disable its local connection. The roster's separately confirmed
`local-disconnect-v1` fallback unassigns only that agent's current roles and
invalidates its usable account/catalog projection atomically. It records provider
authorization Unknown and sign-out Not attempted, never successful logout. The
provider-owned credential/profile files are not read, copied, deleted or changed.
Existing battle, busy, expected-revision and session/form gates still apply;
state/events commit before broadcast. Replayed local receipts cannot become
native operations after executable repair. Verified native logout keeps its
existing intent, exact executable, scoped profile and cleanup protocol.

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


## Automatic planning cards (R040m)

New Create tasks consent includes a versioned automatic-card intent. The same
closed proposal/model/source validation runs before any draft write; expired,
cancelled or lost claims create no cards. Completion, the whole graph and its
existing import receipts/events share one immediate SQLite transaction. Model
text becomes Specs drafts only; it cannot authorize tools, policy or execution.
Old consent tokens cannot authorize this new intent, and old requests never
auto-import during reload or recovery. No new provider or filesystem capability.

## Folder planning snapshots (R040l)

**Read project folder** authorizes the `folder-documents-v1` local read only. It
revalidates the registered root, enumerates through pinned directory descriptors
and reuses the no-follow/nonblocking single-link regular-file reader. Limits:
2,000 entries, six nested directory levels, 16 files, 16,384 bytes per file and
65,536 bytes total; invalid UTF-8/control text also consumes the read budget.
The native 15-second deadline, cancellation and 25-second ledger claim remain.
Files are never truncated. Skips have bounded reason counts; partial coverage and
empty sources are explicit. No Git/config command is run or inferred from files.

Within the bounded inventory, `docs/` sorts first. Eligible suffixes are `md txt
ex exs rs js jsx ts tsx py rb go swift java kt c h cpp hpp css html heex sql json
toml yaml yml`. Existing unsafe relative-path rules still apply. Every dot-prefixed
component and `secret*`, `credential*`, `token*` is excluded, as are `node_modules`,
`deps`, `_build`, `target`, `build`, `dist`, `vendor`, `coverage`, `venv` and
`__pycache__`. Symlinks, hardlinks and special files are skipped without contents.
These filename rules are not a secret scanner; users inspect exact snapshots
before separate provider-use consent.

The same scoped preview command retains exact text/hash snapshots locally. Empty,
cancelled, expired or foreign previews never bypass brief/consent checks. New
`brief-plan-v3` allows 16 frozen source indices and bounded 512 KiB encoded stdin
for the helper; old v1/v2 contracts keep their limits. The provider receives
untrusted snapshot text, not the Arena path, filesystem access or new tools.
The existing no-tools scratch grant, output bounds and completion checks stay.

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

R040i specification acceptance writes only a UUID-named `.md` file beneath the
private app-owned `specifications/` directory. It never uses model/user paths or
touches Arena files. Persist consented revision/text/hash intent before I/O; use
exclusive creation, directory mode 0700, file mode 0600 and file sync. Reject
symlink components; downloads require a bounded regular single-link private file,
stable metadata and matching SHA-256. Existing or partial files are never overwritten.

The Markdown is bounded to 256 KiB and user/model text is fenced as literal text.
HEEx previews escape it; authenticated downloads send an attachment with nosniff
and no-store. Only canonical textual UUIDs for completed acceptances resolve files
or download names (Ecto also accepts binary UUID aliases). Pending, cancelled,
foreign command kinds and expired sessions cannot download. Late/stale completion
cannot move a task or record acceptance. Missing/changed artifacts never become
valid merely because a historical DB receipt exists. Reacceptance writes a new file.

These app-owned storage checks follow the existing same-user trust boundary, not
the descriptor-relative untrusted Arena reader. They do not defeat a hostile
same-user process racing path replacement or arbitrary disk failure. A lost or
changed file is reported; Cuckoding does not silently regenerate acceptance.
This grants no provider access, command execution, repository write or publication.


R040j check declarations are configuration from the authenticated user only. The
closed bounded schema permits literal argv, a relative directory and a finite
timeout; it rejects extra environment/network/grant keys, RTK wrappers, paths as
executables, path traversal and control characters. Previewed content is escaped;
changed content/scope/revision clears consent. Every save/removal needs explicit
confirmation and an atomic revision/event. Stale/recovered forms cannot silently
rebase their edits, and expired sessions cannot save. No provider/filesystem reader
feeds this trusted configuration path. Event data omits command text.

Validation checks declaration structure, not command safety or tool availability.
Arguments such as quotes, spaces or shell-looking text remain exact data. An
explicit interpreter/program may interpret arguments or run repository code;
there is no claim that these strings enforce confinement. Nothing is resolved,
read or executed in this slice. Future admission must verify executable identity,
owned worktree paths (including symlinks), permitted operation, child environment,
actual runtime grants and candidate-bound receipts. Do not put credentials in
stored arguments. Saving checks does not grant network, file or process access.

R050a Battle preview is protected by the existing session mount/event/update
guards and validates Arena/Tabula scope before reading their evidence. It reuses
private artifact hash/path checks and catalog executable-metadata checks, reads
no Arena files and launches no command. Task/role/check text is escaped. A stale
preview retains visibly historical details; Refresh creates no authorization.
Recorded Git HEADs cannot establish current folder identity or cleanliness, and
catalog/model diagnostics cannot establish repository grants. The future Start
boundary must revalidate those facts independently. No hidden reasoning or new
provider data is collected; no state transition means no synthetic audit event.

## R050b isolated checkout boundary

Separate confirmation binds the latest successful inspect/initial-commit receipt
(under five minutes old), source directory identity and generated private path.
The existing native directory lock serializes cooperating operations. A bounded
`ls-tree` preflight accepts regular blobs only: at most 10,000 files, 240-byte paths,
8 MiB per blob, 64 MiB total and 1 MiB listing. Traversal, known credential names,
case-colliding paths, symlinks and submodules are refused. These name checks do not
prove committed files contain no secrets; no file content is sent to a provider.

The helper refuses configured `filter.*` drivers, external Git config/metadata,
and changed HEAD/config; it disables hooks, fsmonitor, external attributes,
autocrlf, sparse checkout, recursive submodules and transport. Git may still apply
committed built-in attributes (for example encoding); the receipt does not claim
raw byte equality. Configuration reads and child output are bounded. No arbitrary
command, network operation or source checkout/index write is introduced. The
locked worktree does add registration under the source `.git/worktrees` directory.

The private UUID parent and `owner.json` are exclusive and precede Git effects.
Failures preserve both files and Git registration; no reset, prune, rollback or
force-removal is attempted. Expired leases cause helper cancellation and cannot
accept a late receipt. Future reuse/removal must revalidate DB, marker, checkout
and Git identities and owned processes. Worktrees share Git metadata; the host
runner and cooperative directory lock are not a sandbox against another process
running as the same user. Concurrent noncooperating filesystem/config mutation
can leave an uncertain result and must never be treated as clean execution proof.

## R050c retained checkout inspection

Inspection accepts only a completed preparation in the selected Arena. The host
freezes its key/HEAD/path/device/inode before launch. Native code derives the UUID
location, validates private parents and exact owner JSON, pins the checkout, and
requires its `.git` candidate to name one immediate child of this source's
`.git/worktrees`. Descriptor-relative reads verify the backlink, `../..` common
directory, UUID lock reason and detached exact HEAD. Foreign pointers are never
used as Git roots. Missing/replaced/linked metadata fails closed.

Fixed `ls-files --stage` reads only the validated index; fixed `cat-file --batch`
reads raw committed blobs from the source object store. Neither calls filters,
uses provider tools nor updates an index. Same R050b tree limits apply; the index
is capped at 8 MiB and batch output at 65 MiB. Tracked file reads pin every path
component, refuse links/special files and check read stability. They compare raw
bytes and executable mode, independently of assume-unchanged/skip-worktree flags.
A descriptor-relative bounded directory walk flags extra names (including ignored
files and empty directories) without reading extra file contents. No names/bytes
enter public receipts. Index/config/ownership are rechecked before reporting.

Built-in Git transformations such as CRLF produce a conservative difference,
even when ordinary Git status would be clean. The inspection never repairs,
prunes, overwrites or resets anything. It is not an atomic filesystem snapshot:
a same-user process may change data immediately or during observation. Execution
must freshly admit and verify its own candidate; a receipt is never a sandbox,
future-integrity guarantee, grant or permission to accept protected policy changes.

## Named profiles and Cursor setup (R020i)

Connection UUIDs are server-owned; profile paths derive only from those IDs.
The legacy `codex` profile remains in place. Commands, results and model choices
bind the exact connection; foreign catalog receipts/stale forms cannot alter it.
Cursor setup supports pinned CLI `2026.09.15-d2fe57e` with fixed `--version`,
`status --format json`, `models`, `login` and `logout` operations only. It cannot
send prompts or launch tools. Inherited environment is cleared; HOME, data/config
and temporary directories stay in the private profile. File credential storage
is forced, browser auto-open, direnv and provider debug logging are disabled. Credentials remain
provider-managed; raw account JSON, identifiers, errors and login text are discarded.

The native helper validates/locks the profile through owned process-group cleanup.
Stdout is bounded to 64 KiB per fixed command, Cursor model rows to 512; stderr is discarded.
Version has five seconds; inspection/logout fifteen; browser login ten minutes,
with monotonic and wall deadlines. The CLI's plain `models` output has a pinned,
strict parser; malformed/partial/duplicate lists never become fresh catalogs.
Unknown formats require adapter updates. No shell, PTY or arbitrary CLI is exposed.
Cursor login links must be HTTPS `cursor.com/loginDeepControl`; Codex's separate
allowlist remains unchanged. Links stay transient behind the authenticated redirect.
The helper owns children, clears inherited secrets and avoids personal profiles;
it is still a host process, not a filesystem sandbox. Cursor inference grants,
login completion/revocation and physical sleep acceptance remain separate.
R020l verifies a real signed-in catalog; catalog metadata never proves inference access.

## Host-owned task tools (R020n)

The runtime retains the no-shell/file/network-tools scratch policy; dynamic calls do not
grant it the worktree directly. The native host rejects unknown tools, foreign
thread/turn IDs, duplicate requests/calls, read-only edits and changed root identity.
Paths are relative ASCII components (eight levels, 240 bytes); hidden, protected
policy, common credential and dependency/output paths are excluded. Opens use
pinned parent descriptors, no-follow/nonblocking flags, and regular single-link
text-file checks. File edits require the current hash; replacement is atomic.
Each call has a fsynced local intent before effects and an outcome afterward.
Failures preserve effects/temporary files and stop the turn; no blind replay.
R020o permits the pure Code Mode interpreter/router only in task sessions, with
effective feature checks; no-tools diagnostics/planning reject it. Provider
scratch permissions do not substitute for the host-service grant. Instructions
state the host read/write authority explicitly without broadening runtime access.
Codex starts its Code Mode host in a separate process group; upstream disconnect
cleanup closes its sessions when stdin ends. Normal fixture cleanup was observed,
but real mid-call crash/cancellation and sleep acceptance remain release gates.

Filename exclusions do not recognize all secrets inside ordinary source files.
The future Start scope must disclose sending eligible contents to the selected
provider. Same-user hostile races remain outside host isolation guarantees.
A tool receipt and a role's `completed` report are not Secutor acceptance.

R050d1 candidate capture uses only host-supplied bounded path/hash pairs, a private
index and fixed Git plumbing. It verifies ownership/registration, untouched tracked
bytes, file modes and extra entries before publishing an app-owned candidate ref.
No hooks, filters, signing, credentials, remote transport or provider Git arguments
are allowed. Existing candidate refs cannot be overwritten. A retained publication
intent without a completed receipt is uncertain and cannot be replayed. Live
verification is a dated observation; same-user hostile races are outside host
isolation guarantees and review/integration still require fresh checks.

## Cursor task execution (R020p)

R020r initial planning is a separate `cursor-plan-no-tools-v1` operation. Only the
consented brief/role instructions/frozen snapshots reach the isolated ACP prompt;
no Arena path or host file service is supplied. Reuse verified deny policy, ask
mode, exact alias/base-model/parameter checks and private store cleanup. Every
native callback aborts; a failed refusal write cannot reclassify that policy error
as a retryable transport failure. ACP input writes use a bounded owned writer so
blocked stdin cannot prevent deadline/cancellation reaching group cleanup.
The host requires a closed Cursor receipt with explicit cleanup, no file-tool
fields and matching grant/transport/model before validated automatic cards. This
is planning authority only, not an execution grant or real-provider acceptance.

The setup helper remains fixed-command only. A separate task entrypoint verifies
version, account and complete catalog, then launches ACP with the selected alias,
empty cwd and per-attempt config/data. Credentials stay in the named private HOME.
No real home, Arena path, personal profile or inherited environment reaches ACP.
The model sees task data and bounded host-service file results only.

A schema-valid generated profile denies all native read/write/shell/MCP/web tools.
Verify it after startup and before/after prompts: this Cursor version silently
resets invalid config to defaults. Ask mode and all resolved model parameters
must match authoritative ACP options. Unknown native requests or tool updates
abort; model text is a proposal to the existing descriptor-bound file service.
Request alias and runtime model/parameters have separate receipt fields.
This is provider-enforced tool restriction, not an OS sandbox around Cursor.

Normal timeout/cancel/error/success verifies owned group closure before removing
provider session stores; uncertainty retains those private stores for inspection.
Only public host effects reach receipts. Thought frames are discarded, never
shown or written to app receipts. Hard process death can leave private provider
session stores under an interrupted attempt; verified recovery cleanup remains
open. Do not classify those files as public logs, export them, or replay the turn.
Fixture and synthetic account evidence must stay separate from full battle,
sleep/crash, and same-user hostile-process acceptance.

## Paused battle authority (R060a)

Pause/Resume are session-protected, battle-scoped and revision-guarded. Neither
control changes task membership, bindings, checks, grants or deadlines. Pausing
allows only the existing claimed stage to finish; stale claims remain refused.
Paused requires settled attempts with verified cleanup: completed work or failed
work explicitly consumed by an eligible R060b retry or R060c Skip. An interrupted pausing
worker cannot become resumable merely because the app restarted. Arena exclusion
and frozen-draft locks persist through both states. Resume rechecks the exact
connection observations; the next stage still performs native path/ref/executable
validation. Wall expiry or exhausted turns cannot be reset by controls.

R060d may recover a running/pausing checkpoint only if all attempts satisfy this
same settled-cleanup rule. Missing process visibility is not evidence of cleanup.
Increment the control revision and record the reason atomically; startup leaves
the battle Paused, never Running. Explicit Resume retains current-binding and
original-budget gates, then native validation before each effect. Completed
receipts are not a guarantee that retained checkout bytes are still unchanged.
Unfinished/native-uncertain attempts remain interrupted and cannot be replayed.

## Settled provider retry (R060b)

New Start snapshots freeze `provider-retry-v1` and the two-retry cap per task/final
scope. Retry uses session/form, exact battle/revision, current binding, deadline
and turn checks. Only the latest matching failed role with a normalized transient
provider receipt and verified cleanup qualifies; every earlier attempt must also
be settled. Preserve explicit cleanup refusal through receipt normalization.
Interrupted claims, missing receipts, native operations, policy errors and blocked
or rejected reviews never acquire retry authority. The new attempt has a fresh ID
and session; writer retry uses a fresh worktree from the unchanged reviewed head.
No abandoned bytes are reused, deleted or integrated. Failed tool/edit receipts
remain visible; raw provider text/thoughts are discarded. No permission expansion,
live-session revival or account/model fallback is added.

R060j permits automatic 5/20-second backoff only in new Starts with
`automatic-provider-backoff-v1`, and only for the same settled retry candidate
with normalized connection/busy/timeout/launch failure and verified cleanup.
Generic provider/turn failures remain manual. Persist the wait before notification;
revalidate exact bindings, limits and deadline at admission under the write lock.
Cancel/Stop/Skip/timing fences close the wait; startup requires manual Retry.
Historical authority and every R060b exclusion stay intact.

## Concurrent Arena admission (R070a)

New `isolated-arenas-v1` Starts share two battle stage workers, one stage per
Arena/battle and one provider turn per exact saved connection. Capacity checks
run under the same immediate SQLite claim transaction as attempt/turn/event
writes. A waiting claim writes nothing. Provider cleanup that is missing or
unverified reserves its connection, including failed/interrupted attempts;
another Arena cannot infer release from a missing process. Native profile locks
and all existing executable/account/worktree preflights remain mandatory.
Legacy Starts and retained integration inspection remain exclusive. The
one_for_all group stops all old workers before recovery. No same-board writable
checkout sharing, new tool grants, account substitution or combined-candidate
acceptance is added.

## Read-only dashboard/activity (R080g)

Dashboard routes retain authenticated LiveView access. Both stateful components
also guard their own events using the server-owned browser session. Scope comes
from the mounted Arena, never event parameters; explicit Arena/board references
take precedence over command fallback and foreign scope cannot be bypassed.
Invalid scope returns no events. Page queries return only ID/kind/time; worker
DTOs keep only public name/kind/connection-name/model fields. No raw event/provider
payload, credential, thought frame or filesystem path is opened by activity.
Paging/following/navigation performs no provider call or authority mutation.

## Explicit task omission (R060c)

Only new `skip-task-v1` snapshots permit Skip. Session/form, exact task/battle/control
revision, current bindings and original budgets are rechecked under the write lock.
Require a clean paused boundary or validated task-local blocked/transient provider
failure/review exhaustion, with all earlier claims settled and verified cleanup.
Never consume native/policy failures, interruption, unknown cleanup or final review
as skippable work. Compute dependent omissions from the frozen graph, not model text.
Retain failed effects and attempts; restart independent tasks from the reviewed head.
Final prompts and criteria digests bind the retained subset and explicit omissions;
configured checks and independent review remain mandatory. Partial is not full
completion. No worktree deletion, original-checkout mutation or authority expansion.
