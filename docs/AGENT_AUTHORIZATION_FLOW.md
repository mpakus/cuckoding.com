# Agent-first authorization flow

Status: shared-profile implementation delivered (task 1018); authenticated
two-project/refresh acceptance remains open. This replaces per-run sign-in as
the normal saved-agent journey in ADR-024. It does not claim provider-specific
acceptance from configuration tests alone.

## User journey

1. Open **Agents** from the main navigation. This is the machine-wide catalog,
   separate from **Agent activity**, which shows running and historical sessions.
2. **Add agent**: name, runtime, executable and provider-specific settings. Save
   once, authorize once, and show the observed connection status and check time.
   The same runtime may have several deliberately separate named accounts.
3. Add a project through **Project → Repository → Review**. In project settings,
   select existing agents and assign their roles; do not re-enter credentials.
   Use Projects to return to the project after adding an agent.
4. Create a board and tasks as before. Several roles may use the same agent.
   An agent entry lists all of its assigned roles, rather than duplicating login
   cards for Specifications and Review.
5. Choose **Start workflow** on a prepared run. Check each distinct connection
   automatically before starting provider work. Do not render login commands as
   the default screen. Authentication checks do not skip policy, budget,
   concurrency, Git, or release-approval gates.
6. Only if a connection needs attention, name that agent, explain the reason,
   and offer **Reconnect agent**. Repair the saved connection once, then retry
   the run without creating a replacement project, board, or task.

"Authorize once" means authorization survives subsequent projects, boards,
runs, and application restarts while the provider session remains valid. It
does not promise that revoked, expired, or administratively restricted access
never needs renewed authorization. Unsupported runtimes must say so before
they can be assigned for execution.

## Ownership and security

- Reuse `provider_accounts`; do not create a second catalog. It owns stable
  identity, non-secret runtime settings, and observed connection status.
- A project owns role assignments, a board owns its versioned workflow and
  defaults, and a run owns the immutable execution snapshot and worktree.
- The selected provider identity is a live authentication dependency. Token
  rotation or revocation does not rewrite execution history.
- Decision confirmed on 2026-09-20: use one app-owned runtime profile per saved
  agent across projects. Provider history and session metadata may be shared.
  Separate named agents get separate profiles. Never use the user's personal
  CLI home. Generated task instructions, permission settings, and worktrees
  remain run-owned; shared state is not reviewed project knowledge.
- Database rows, events, logs, prompts, artifacts, clipboard commands, and
  exported configuration contain no credential values. Provider-native storage
  remains responsible for secrets; choosing Keychain alone is not evidence
  that two distinct runtime homes resolve the same login.
- Shared profiles are now explicitly approved. Codex uses the same account
  home for login, probes and execution, with saved execution config ignored.
  Cursor shares its app-owned HOME but keeps task configuration run-owned.
- Editing a shared agent asks for confirmation of its cross-project impact.
  Record a value-free audit event before broadcasting status.
  Future launches must fail clearly after revocation; do not silently switch
  to another account or restart/kill existing work.

## Existing boards and runs

Do not match old connections to accounts by display name alone, silently mutate
historical snapshots, or require users to abandon boards containing their tasks.
Provide an explicit **Connect saved agents** upgrade for a board. Preview its
roles and the chosen account IDs, then persist an audited assignment revision
used by future runs. Existing tasks and history stay on the board. Already
prepared runs retain their snapshot; offer an explicit validated binding for
queued work or a safe replacement-run action, without deleting the old run.
Running/completed runs are never rewritten.

## Implementation order and acceptance

1. Prove the credential boundary for the installed, pinned runtime versions.
   One login must authenticate isolated runs in two projects, survive restart
   and refresh, and fail safely after revocation. Check global writes and MCP
   process startup as well as a successful status command. Do not read or print
   a user's token to establish this evidence.
2. Build the independent Agents catalog with add/edit/connect/check/reconnect
   actions using existing domain validation and LiveView conventions. Project
   settings select accounts and assign roles.
3. Resolve and verify unique connection identities at the shared runtime
   boundary, then reuse the result for every assigned role. Deduplicate by
   account ID and relevant snapshotted execution settings, never runtime name
   alone. A saved status is not proof of current authorization.
4. Add the reviewed legacy-board/queued-run upgrade path. Explain impact and
   preserve all task, event, artifact, and snapshot history.
5. Verify duplicate-role display, two-account separation, revoked/unavailable
   providers, reconnect, app restart, concurrent runs/refresh, secret canaries,
   path confinement, keyboard behavior, and LiveView status refresh. Record
   mock/fixture checks separately from real-provider acceptance.

## Implemented and remaining verification

- `/settings/agents` provides add/edit, copyable sign-in commands and async checks;
  status updates arrive after durable provider audit events. Project settings
  retain existing add/edit controls for compatibility and can attach accounts.
- Codex login, probe and launch now resolve the same account-owned home, with
  Keychain selection passed at launch as well as login. Per-run instructions and
  permission overrides do not overwrite shared configuration.
- Cursor shares only the approved app-owned HOME during launch; task config and
  compatibility directories remain per-run. Fixed shared sandbox/MCP files are
  checked against expected contents and unsafe paths fail closed.
- Claude Code has a reusable reviewed helper; OpenCode and Custom Agent remain
  setup-only and cannot be advertised as working reusable launch adapters.
- Saved-agent cards group assigned roles; legacy unbound roles have an explicit
  selector. A board upgrade matches stable connection keys and compatible
  executable/helper settings, never names. A queued binding is a separate event.
- Deterministic regression tests cover profile reuse across two project-shaped
  runs, distinct accounts, invalid/symlink paths, revoked probes, changed shared
  MCP files, separate task settings and historical snapshot preservation.
- Real CLI status checks on 2026-09-20 returned sign-in required for both existing
  app-owned accounts. No credentials were read/copied and no paid task launched.
  Sign in once per saved profile, then verify authenticated two-project use,
  token refresh/restart and concurrent provider behavior before closing task 1018.
- Per-project impact lists and revoke/delete controls remain follow-ups. This
  tranche does not log out personal profiles or delete any credential storage.

Official Codex documentation describes cached login reuse and file/keyring
storage; Cuckoding now avoids the former cross-home assumption:
[Authentication](https://learn.chatgpt.com/docs/auth).
