# Security Model

## Security objective

Cuckoding runs powerful agent runtimes on a developer machine against untrusted repository content, without container isolation in the MVP. The design must constrain what Cuckoding itself grants, make the runtime's own permission grant explicit and recorded, protect credentials, preserve trustworthy audit evidence, require humans at irreversible boundaries, and never claim isolation it does not have.

`docs/TRUSTED_HOST_THREAT_MODEL.md` enumerates assets and attackers, maps every boundary to risks and validation tasks, records the malicious-repository tabletop, and states the residual risks disclosed by the MVP.

## Trust boundaries

- Menubar shell ↔ local Phoenix service.
- Browser session ↔ Phoenix service.
- Phoenix control plane ↔ agent runtime process (host).
- Run A worktree ↔ Run B worktree and the rest of the filesystem.
- Project A ↔ Project B (knowledge, ports, worktrees).
- Application ↔ plugins.
- Application ↔ GitHub/provider credentials.
- Untrusted repository/model/plugin output ↔ trusted commands and policy.
- Local application ↔ update and optional telemetry endpoints.

## Threats and controls

| Threat | Required controls |
| --- | --- |
| Unauthorized local web access | Loopback bind, one-time bootstrap secret, single-use `/open` tokens, short-lived cookie sessions, origin/host checks, CSRF, optional re-auth after sleep |
| Prompt injection from repository | Separate trusted instructions from data; least-privilege runtime permission grant configured by the adapter; protected paths; approvals; no output-to-command promotion |
| Secret theft | Keychain references; no secrets in agent environment or argv; provider CLIs use their own auth; environment allowlist; argument/environment scrubbing; redaction tests |
| Host mutation outside the worktree | Path confinement for Cuckoding-executed commands; runtime permission grant limited to the worktree; protected paths flagged; honest limitation notice |
| Cross-run and cross-project leakage | Worktree per run; port ranges; knowledge scope; per-run generated runtime configuration; tests |
| Config self-escalation | Trusted config hash; changed execution policy or plugin set requires independent human approval |
| Destructive Git action | Host-side constrained Git service; protected branches; explicit approval; no force-push |
| Project-folder initialization | Native folder selection, canonical root validation, a review that names the pending Git mutation, and no initialization or commit before explicit confirmation |
| Forged completion | Typed artifact schemas, exit-code checks, independent QA, immutable event sequence |
| Cost/resource denial | Per-stage and global budgets, concurrency limits, pause/hibernate, alerts, unattended-mode caps |
| Malicious plugin | Manifest permissions, user approval to enable, supervised process, untrusted output, no secret access without declaration |
| Malicious update | Signature verification, pinned update endpoint, rollback, migration backup, provenance/SBOM |
| Knowledge poisoning | Evidence requirements, redaction, project scope, human publication review, validity/supersession/revocation, usage feedback |

## Capability model

Each stage receives an unguessable short-lived capability set: allowed worktree, tool categories, network class (advisory on the host runner), secret references (Cuckoding-managed only), knowledge namespaces, plugin set, budget, expiry, approval requirements. The adapter maps tool categories and worktree onto the runtime's permission settings and records the effective grant. Capabilities can be narrowed but not expanded by an agent or a plugin.

Plugin discovery treats manifests as untrusted input: it accepts only regular,
non-symlinked files below configured plugin roots, a closed schema, confined
permission roots, and fixed single-argument version probes executed without a
shell. Discovery never enables a plugin. Activation requires an explicit reason
and approval class, persists an event before the projection changes, and may
only narrow an enabled ancestor grant. `none`, `loopback`, and `external` are
stored as distinct grants; on the host runner they remain approval and runtime
configuration boundaries, not a claim of network sandboxing.

Plugin invocation uses a signed token with a maximum fifteen-minute lifetime
(five minutes by default). Verification re-resolves the current activation and
requires the signed run, plugin, activation, optional stage/role, permission
map, approved configuration, manifest hash, and network class to match;
activation revocation or mutation fails closed.
Public results reject unlabeled numbers, unknown shapes, private fields from
non-secret plugins, and payloads over 1 MiB. Plugin failures collapse to a
public `plugin_failed` error so raw third-party errors are not promoted into
trusted output.

Reference adapters do not accept model-selected executables, namespaces, MCP
packages, integrity values, roots, or unreviewed tools. RTK resolves the
underlying trusted command before adding its wrapper. XERJ namespaces come from
the run's project and board records. The filesystem MCP package is exact and
offline with no write tools, secrets, or network permission; because it remains
a host process, these controls are not described as OS isolation.

## Secrets

- `SecretStore` is owned by the Phoenix process: macOS Keychain through the `security` CLI (MVP) or a small native library later; the database holds opaque references only.
- The CLI implementation invokes absolute `/usr/bin/security` paths and sends new values over stdin, never argv. Reads are audited by opaque reference, declared purpose, optional run, and timestamp. A future native implementation replaces only the behaviour adapter with Security.framework calls; reference and audit semantics remain unchanged.
- Provider authentication belongs to the runtime (Claude Code, Codex, Cursor, OpenCode logins); Cuckoding probes status and never copies credential directories.
- Claude Code bare-mode authentication may use only a host-approved absolute executable helper referenced from run-scoped settings. Helper presence is not treated as successful authentication; an isolated probe must confirm it. Global OAuth state never causes Cuckoding to expose the real home directory or copy credential files into a run.
- Codex authentication and session state use a run-scoped `CODEX_HOME`. A global ChatGPT login is not copied or exposed; the adapter remains unavailable until the scoped home passes a separate authentication probe. Cuckoding never passes an API key to the agent subprocess.
- Cursor Agent never receives the real home directory. Each run gets owner-only `HOME`, `CURSOR_CONFIG_DIR`, and `CLAUDE_CONFIG_DIR` paths and requires a separate login there, so the retained user-global transcript/MCP failure cannot reuse global state. The adapter writes an empty run-owned MCP file and refuses project Cursor CLI, sandbox, MCP, or plugin overrides plus plugin directories created inside the isolated profile; an MCP call deny alone is still not treated as process isolation. OpenCode remains a stub until its separate CLI and isolation boundaries are verified; the desktop app alone grants no capability.
- GitHub credentials are fetched from `SecretStore` only inside the host-side VCS service after approval. They are supplied to the constrained Git process through ephemeral environment configuration and to the fixed `https://api.github.com` endpoint through an authorization header; they are never added to an agent grant, command payload, event, artifact, remote URL, or pull-request body.
- The Phase 4 local VCS host accepts only an absolute existing bare `origin`, the exact approved run and recorded clean candidate SHA, disables terminal prompting, constructs a non-force `refs/heads/<branch>:refs/heads/<branch>` refspec, and records the result. It never receives provider credentials or performs merge.
- Never persist complete environment maps, authorization headers, or CLI arguments containing secrets.
- Redact before disk, UI broadcast, analytics export, and knowledge extraction.
- The shared recursive redactor replaces configured canary values in strings and removes authorization, cookie, password, secret, token, complete environment, and argv fields before those boundaries.
- Rotate or revoke credentials after any suspected exposure and record an incident.

## Local service hardening

- Random port on `127.0.0.1`; never bind `0.0.0.0`.
- Bootstrap token passed via file descriptor or 0600 file, never argv or logs; exchanged once.
- Strict origin and host validation; secure cookies and CSRF.
- Disable debug endpoints and source disclosure in release builds.
- Artifact serving by authorized opaque IDs, not paths.

The production shell uses a unique regular mode-0600 file containing separate
per-launch session-signing and bootstrap secrets. Runtime configuration reads
the signing secret, the supervised auth process deletes the file before READY,
and the bootstrap exchange is then consumed exactly once. Shell bearer tokens
remain in memory; browser handoff tokens expire after 60 seconds and are removed
on their first use. If shell authentication is configured but its process is
unavailable, browser authorization remains fail-closed.

The updater embeds only an HTTPS metadata endpoint and the Tauri public
verification key. The private updater key is release-only. Downloaded bytes
are not installed until Tauri verifies their detached signature. Phoenix
requires shell authentication for every update transition, records the
attempt before snapshotting, writes a private pending marker, and rejects
forward migration of an existing database without that marker. Backups and
manifests are owner-only and hash-verified; symlinks and path escape are
rejected. Rollback preserves the failed database before restoring compatible
data, and an older binary refuses any unknown applied migration.

Diagnostics export is an authenticated, explicit local action. Its schema is a
fixed allowlist of bounded summaries, not a log collector: source, prompts,
provider and command output, credentials, argv, environment variables, private
paths, plugin manifests, and free-form errors are excluded before serialization.
Every JSON member is redacted again, written to an owner-only archive beneath a
non-symlinked application-data directory, and disclosed in the settings UI
before creation. There is no switch that expands the bundle to sensitive data.

## Process safety

- Child processes in their own process groups; PID plus start identity recorded.
- Timeouts and termination ladders; every step recorded.
- Cuckoding-executed repository commands come only from the run's immutable trusted configuration snapshot and are launched without a shell. This narrows command injection but does not turn a trusted-host child into a sandbox.
- Protected-path QA approvals are scoped to a digest of the exact changed path set. Approval decisions use a pending-only atomic update and append a durable event, so they cannot be silently overwritten or reused for a broader later diff.
- Redact stdout/stderr before persistence.
- Build child environments from scratch; reject undeclared and credential-shaped variables instead of inheriting the Phoenix environment.
- All provider and plugin output is data until parsed and validated.
- Adapter event normalization accepts only the closed public event vocabulary, recursively redacts summaries and metadata, and fails closed on malformed or unknown provider output.
- Generated runtime configuration stays in the run's `agent/` directory with owner-only permissions; adapters reject a symlinked configuration directory and never write user-global runtime configuration.
- On restart or wake, inspect and reconcile before killing or adopting a process.

## Audit events

At minimum: authentication changes, capability grants, effective runtime permission grants, policy exceptions, plugin enablement and permission changes, stage transitions, approvals, secret reference use, process group creation/destruction, Git push/PR creation, knowledge publication/revocation, update installation, destructive retention actions, sleep gaps and reconciliation outcomes.

Rejected shell/browser authorization and loopback-boundary requests are stored
in append-only `security_audit_events`. The closed record contains only event
type, HTTP method, route path without its query string, response status, and UTC
time. Authorization headers, tokens, origins, hosts, IP addresses, and arbitrary
descriptions are never accepted by this audit boundary.

## Human approval gates

Preview URLs and probes accept only `http://127.0.0.1:<allocated-port>`; health paths reject CR/LF injection and redirects are not followed. Listener recovery uses `/usr/sbin/lsof`, the process-group leader, and its recorded start identity, and ambiguous output fails closed. Finder/editor actions operate only on the database-recorded worktree after physical path resolution and invoke absolute `/usr/bin/open` with argv.

Lifecycle cleanup fails closed unless the database relationship, canonical workspace paths, ownership marker, base/branch/head identities, clean Git status, and lack of running process records all agree. It never uses force removal, preserves the run directory and artifacts, and records cleanup intent before invoking Git so startup reconciliation can diagnose an interrupted cleanup.

The power manager launches only absolute system binaries behind `/usr/bin/env -i`, records the assertion PID and start identity, and refuses to signal a reused PID. Unattended mode changes assertion eligibility only: pending approvals remain pending and no capability, policy, budget, push, or merge gate is bypassed.

Mandatory for policy escalation, newly modified execution configuration, enabling plugins with host or network permissions, destructive cleanup with uncertain ownership, global knowledge publication, external push/PR, final merge/release, and installation of untrusted skills or binaries.

## Security verification

`docs/SECURITY_TEST_MATRIX.md` maps risks R1–R14 to current executable evidence
and keeps the residual physical-machine, provider, signing, and reviewer gates
explicit.

- Threat-model review before beta and after material architecture changes.
- Path traversal and symlink race tests on confinement.
- Prompt injection and tool-output forgery fixtures.
- Knowledge retrieval capabilities store only a SHA-256 token hash, expire
  after a bounded interval, and are resolved back through the recorded
  project/run/stage ownership chain. Project items never cross that chain;
  global items additionally require the run's trusted policy snapshot to opt
  in. Retrieval queries are not persisted in plaintext.
- Secret canary tests across logs, database, UI, exports, and knowledge files.
- Local unauthorized browser/session and token replay tests.
- Cross-project knowledge and port isolation tests.
- Plugin permission tests: undeclared access is refused and audited.
- Dependency, binary provenance, and updater verification.
- Recovery exercises that preserve evidence after forced termination and sleep.
