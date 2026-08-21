# Testing Strategy

## 1. Principles

- Prefer deterministic offline tests.
- Test normalized protocols with fixtures before live providers.
- Exercise concurrency with real processes where unit mocks hide races.
- Treat crash recovery as a product feature.
- Never require paid provider calls for the default test suite.
- Test internal A2A entirely with fake providers before any live-provider run.
- Preserve failing worktree fixtures for diagnostics only in isolated temporary directories.

## 2. Test layers

### Unit tests

Pure modules and changesets:

- path canonicalization and overlap;
- lease compatibility;
- state transitions;
- capability authorization;
- message routing;
- Agent Card validation and capability filtering;
- task/delegation transition mapping;
- message part validation and delivery ordering;
- idempotency request hashing and replay;
- artifact reference and revision validation;
- provider event normalization;
- redaction;
- retention decisions;
- XERJ result normalization.

### OTP/process tests

- DynamicSupervisor session lifecycle;
- Registry lookup without atom leaks;
- provider process crash handling;
- heartbeat and lease expiry;
- PubSub after-commit behavior;
- backpressure and bounded buffers;
- project runtime isolation;
- application restart reconciliation.
- A2A supervisor, AgentDirectory, TaskCoordinator, MessageRouter, and ArtifactRegistry restart isolation;

### Database tests

- migrations from an empty database;
- foreign-key enforcement;
- lease transaction races;
- message delivery idempotency;
- Agent Card revision ownership;
- delegation accept/reject/expire/revoke races;
- per-recipient inbox sequence monotonicity;
- A2A idempotency-key replay/conflict;
- context participant authorization;
- artifact integrity/revision constraints;
- event append behavior;
- busy retry boundaries;
- retention safety;
- backup/restore smoke test.

### Provider contract tests

Use recorded and hand-authored JSONL fixtures for:

- Codex App Server handshake and stream;
- Codex approval requests;
- Codex interrupt/resume;
- Codex `exec --json` fallback;
- Claude structured streaming;
- Cursor ACP initialize/authenticate/new-load session/update/permission/cancel flows or explicit capability downgrade;
- Cursor unknown blocking and notification extension methods;
- Cursor headless one-shot capability downgrade;
- OpenCode ACP initialize/new-load session/update/permission/cancel flows or explicit capability downgrade;
- OpenCode model/provider metadata normalization;
- shared ACP request correlation with interleaved Cursor and OpenCode fixtures;
- malformed and partial protocol lines;
- provider version incompatibility;
- stderr diagnostics and unexpected exit.

### MCP contract tests

- initialization and tool discovery;
- authenticated identity binding;
- expired/revoked capability;
- forbidden cross-project access;
- claim, renew, release, and expiry;
- direct/task/project messages;
- cursor pagination and acknowledgement;
- handoff validation;
- search unavailable behavior;
- rate and size limits.

### Internal A2A contract tests

- automatic `hub_register` and safe Agent Card publication for every provider adapter;
- SDK JSONL handshake/prompt/usage fixture lifecycle;
- remote attach without a child Port, connect.env 0600, token absent from Agent Cards;
- peer list/get/find filtering without secret or cross-project leakage;
- context creation and participant authorization;
- delegation propose, accept, reject, expire, revoke, redirect, and conflicting acceptance;
- atomic accepted-delegation/task assignment;
- direct, task, context, project, and system routing;
- text, structured data, artifact reference, and approved file reference parts;
- arbitrary URL, traversal, foreign artifact, oversized part, and unknown schema rejection;
- stable per-recipient ordering under fan-out;
- pending, injected, acknowledged, expired, and skipped delivery transitions;
- same-key/same-request replay and same-key/different-request conflict;
- task optimistic-version conflict and cancellation preservation;
- artifact publish, hash mismatch, missing bytes, quarantine, and revision lineage;
- task subscription reconnect through durable reload rather than PubSub replay;
- autonomous delegation depth, fan-out, concurrency, rate, and permission policy;
- restart recovery with pending messages and delegations but no duplicate provider injection.

### LiveView tests

- create and close tabs;
- session state changes;
- streaming activity batching;
- approval response;
- lease conflict panel;
- unread messages;
- Agents directory and capability filters;
- delegation inbox actions and expiry;
- task conversation delivery states;
- artifact integrity/revision panel;
- handoff review;
- search disabled/stale/ready states;
- team sync bundle export;
- destructive cleanup confirmation.

### End-to-end desktop tests

- open a repository;
- run two fake providers concurrently;
- discover peers, delegate a task, exchange structured messages, publish an artifact, and acknowledge delivery;
- claim conflicting resources;
- simulate crash/restart;
- preserve dirty worktrees;
- opt-in Compose on a worktree, reject LAN binds, skip containers on the primary tree;
- package and launch the ExTauri application;
- close the native window and verify child cleanup.

## 3. Required concurrency scenarios

1. Two agents request the same file simultaneously; exactly one exclusive claim succeeds.
2. A directory or glob lease blocks a child file claim.
3. Two shared leases coexist; a later exclusive claim fails.
4. A lease expires while its owner process is dead.
5. A delayed heartbeat cannot resurrect an expired lease.
6. App restart expires stale active leases deterministically.
7. A provider edits without a lease; the file is preserved and a violation is emitted.
8. Two isolated worktrees modify the same logical file; both changes survive and merge conflict is visible.
9. SQLite returns busy during contention; bounded retry succeeds or reports a stable error.
10. One project runtime crashes without releasing another project's resources.
11. Two senders retry the same semantic delegation; the authenticated idempotency key prevents duplication.
12. Two recipients race to accept reassignment of the same task; only one valid assignment commits.
13. A project broadcast creates one ordered delivery per eligible recipient without cross-project fan-out.
14. A recipient crashes after injection but before acknowledgement; restart shows the uncertain delivery without silently duplicating the prompt.
15. A recursive delegation reaches policy depth; the next proposal is rejected deterministically.
16. An agent accepts a task but fails to acquire a file lease; task becomes blocked and existing ownership remains intact.
17. A handoff with failing required checks cannot merge; a passing accepted handoff merges only after an explicit user action.
18. A dependent task stays blocked until every prerequisite is `completed`; cycles are rejected.

## 4. Fake provider

Build a small deterministic test executable or Elixir port fixture supporting:

- JSONL handshake plus an ACP mode with JSON-RPC requests and notifications;
- scripted token/message deltas;
- command and file-change events;
- approval requests;
- configurable delay;
- malformed output;
- crash on demand;
- ignored graceful termination;
- resume token.
- internal A2A Agent Card profile;
- scripted delegation decisions and acknowledgement timing;
- safe-boundary delivery hooks;
- idempotent restart cursor.

Keep provider-specific fixture directories for `codex`, `claude`, `cursor`, and `opencode`. Cursor and OpenCode must also run against the same shared ACP transport contract suite so transport fixes cannot regress only one adapter.

This fixture is the basis for CI and load tests without provider accounts.

## 5. Search tests

- index a small fixture repository;
- query literal, semantic, and hybrid paths when enabled;
- verify source attribution and result budgets;
- verify exclusions for secrets/build output;
- delete XERJ data and rebuild;
- kill XERJ during indexing;
- ensure core agent operations continue while search is unavailable;
- verify namespace isolation across projects and agents.

## 6. Security tests

- `../` traversal and absolute path injection;
- symlink escape;
- case-normalization behavior on macOS;
- shell metacharacters in prompts and paths;
- forged agent/project IDs;
- forged Agent Card identity/provider fields;
- cross-context/task inbox access;
- recursive/fan-out delegation abuse;
- idempotency-key reuse with changed payload;
- foreign, traversal, remote-URL, missing, and hash-mismatched artifact/file references;
- stolen but expired capability;
- oversized MCP payload;
- secret fixtures in output/transcripts;
- non-loopback listener detection;
- cleanup path mismatch;
- PID reuse/process ownership mismatch.

## 7. Performance targets for MVP

These are initial budgets, to be measured and revised:

- project shell usable within 3 seconds after backend readiness on a development Mac;
- streamed UI update latency under 150 ms at normal event rates;
- lease decision p95 under 50 ms locally;
- four simulated agents without unbounded memory growth;
- four-agent A2A broadcast/delegation p95 under 100 ms excluding provider inference;
- 10,000 pending/acknowledged deliveries recover without duplicate sequence numbers;
- 100,000 stored normalized events remain queryable in the UI;
- a 60-minute transcript does not require all content in LiveView assigns.

## 8. CI gates

```bash
mix check
```

`mix check` runs format, compilation with warnings as errors, tests, Credo, Dialyzer, and Sobelow.

Additional jobs:

- migration smoke test;
- provider fixture conformance;
- internal A2A contract and migration conformance;
- dependency/license scan;
- macOS ExTauri build smoke test;
- optional live-provider nightly tests using dedicated credentials and strict budgets.

## 9. Definition of a regression fixture

Every provider protocol bug, lease race, data-loss risk, or crash-recovery bug must add a minimal deterministic fixture or reproduction test before the fix is considered complete.
