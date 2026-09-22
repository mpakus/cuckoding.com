# Agent-first authorization flow

Status: shared-profile implementation delivered (task 1018); authenticated
two-project/refresh acceptance remains open. This replaces per-run sign-in as
the normal saved-agent journey in ADR-024. It does not claim provider-specific
acceptance from configuration tests alone.

## User journey

1. Open **Agents** from the main navigation. This is the machine-wide catalog,
   separate from **Agent activity**, which shows running and historical sessions.
2. **Add agent** follows three steps: **Name and runtime**; **Authorization**;
   **Model**. The executable is suggested from the installed CLI when possible,
   and an absolute-path field remains available when it is not found. The second
   step saves the agent, reuses a compatible Codex/Cursor sign-in by default,
   and shows a copyable sign-in command only when needed. **Use a separate
   sign-in** creates an independent account. After sign-in, **Check sign-in and
   fetch models** verifies the app-owned provider profile and refreshes its
   catalog; a connected shared account can continue without a second login.
   The final step selects a discovered model or runtime default. A validated
   Custom model ID remains available when discovery is unsupported or unavailable.
   For Codex, a discovered model also exposes only its reported reasoning levels;
   **Model default** leaves the effort to Codex. Other runtimes do not present an
   unverified reasoning override. Closing setup after step two leaves the saved
   agent in the catalog for later completion.
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
   and offer **Re-authorize agent**. Repair the saved connection once, then retry
   the run without creating a replacement project, board, or task.

"Authorize once" means authorization survives subsequent projects, boards,
runs, and application restarts while the provider session remains valid. It
does not promise that revoked, expired, or administratively restricted access
never needs renewed authorization. Unsupported runtimes must say so before
they can be assigned for execution.

No Cuckoding timer clears authorization on restart or after a run. Provider-native
storage and refresh determine its lifetime; years-long validity cannot be set by
Cuckoding. Only the provider runtime handles token values. See
[official Codex authentication documentation](https://learn.chatgpt.com/docs/auth).

## Ownership and security

- Reuse `provider_accounts`; do not create a second catalog. It owns stable
  identity, non-secret runtime settings, and observed connection status.
- A project owns role assignments, a board owns its versioned workflow and
  defaults, and a run owns the immutable execution snapshot and worktree.
- The selected provider identity is a live authentication dependency. Token
  rotation or revocation does not rewrite execution history.
- Decision confirmed on 2026-09-20: use one app-owned runtime profile per saved
  agent across projects. Provider history and session metadata may be shared.
  ADR-026 allows multiple named agents to reference the same provider profile;
  only an explicit separate sign-in gets a separate profile. Never use the user's personal
  CLI home. Generated task instructions, permission settings, and worktrees
  remain run-owned; shared state is not reviewed project knowledge.
- Database rows, events, logs, prompts, artifacts, clipboard commands, and
  exported configuration contain no credential values. Provider-native storage
  remains responsible for secrets. Codex and Cursor native file stores are confined
  to private app-owned profiles; Cuckoding never reads or copies their token files.
- Provider model discovery runs only after the scoped authorization probe. The
  database stores bounded model IDs, display labels, validated Codex reasoning
  levels, and discovery status,
  never raw CLI output or provider errors. Codex uses the official app-server
  `model/list` method; Cursor uses its account-scoped `models` command.
- `provider_accounts.authorization_account_id` points only to a compatible root
  account (same runtime/executable/helper). New automatic selection prefers a
  connected root, then the oldest compatible root. Existing accounts remain
  independent unless newly created with a shared reference. References cannot be
  redirected later, preventing silent identity changes to historical runs.
- Each agent's model and Codex reasoning level remain independent. Project
  settings copy both; boards and runs preserve them in snapshots. Planning and
  workflow requests forward the selected model and per-role reasoning level;
  reported actual model stays separate. Changing the model in project settings
  clears a copied reasoning level so an unsupported combination is not retained.
- Shared profiles are now explicitly approved. Codex uses the same account
  home for login, probes and execution, with saved execution config ignored.
  Cursor shares its app-owned HOME and native credential file but keeps task
  configuration run-owned.
- Editing and status checks record a value-free audit event before broadcasting
  status. Future launches fail clearly after revocation; they do not silently
  switch to another account or restart/kill existing work. Root account cards
  list every current project/board role using that sign-in. **Disconnect shared
  sign-in** requires confirmation, records the request before invoking the
  provider's scoped logout, records `provider.authorization_disconnected`, and blocks future launches for all
  linked agents without rewriting running work or historical snapshots.

## Existing boards and runs

Do not match old connections to accounts by display name alone, silently mutate
historical snapshots, or require users to abandon boards containing their tasks.
Provide an explicit **Connect saved agents** upgrade for a board. Preview its
roles and the chosen account IDs, then persist an audited assignment revision
used by future runs. Existing tasks and history stay on the board. Already
prepared runs retain their snapshot; offer an explicit validated binding for
queued work or a safe replacement-run action, without deleting the old run.
Running/completed runs are never rewritten.

On a queued legacy run, **Choose saved agent** lists only accounts with matching
runtime and executable/helper settings. Choosing an option does not submit or
show a confirmation; **Connect saved agent** confirms the audited binding.
Connected accounts show a green, text-labeled status and a **Re-authorize agent**
link. Run-local sign-in commands are not shown; an authenticated account's
one-time command stays collapsed under **Re-authorize agent** in Agents.

For Codex, a prior "Connected" observation cannot override a missing private
`CODEX_HOME/auth.json` in the app-owned file store. The CLI must report signed
in **and** that regular owner-only file must exist. Run start rechecks each
distinct saved sign-in and records its latest status before execution. If one
needs sign-in, the run stays queued, names that agent, and links to its Agents
card; the task and worktree remain unchanged. A user who signed in before the
keyring-to-file-store change must complete one new sign-in for this app-owned
profile. Later runs reuse it until the provider revokes or expires it.

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

- `/settings/agents` provides a three-step add wizard, full edit form, copyable sign-in commands and async checks;
  status updates arrive after durable provider audit events. Project settings
  retain existing add/edit controls for compatibility and can attach accounts.
- Codex and Cursor authorization checks also refresh a bounded provider model
  catalog. The root sign-in owns the catalog; linked agents immediately reuse it,
  and editing an agent preserves it. Discovery failure does not discard a valid
  sign-in and is shown separately from authentication status.
- Linked agents show shared live status and a link to the original sign-in card,
  not a second login command. Model/name edits do not clear authorization status.
- Codex login, probe, model discovery, launch and logout now select the file store
  in the same account-owned home. An existing Keychain login does not transfer;
  sign in again through Agents. The provider's `auth.json` must be a regular
  owner-only file. Per-run instructions and permission overrides do not overwrite
  shared configuration.
- Cursor uses `AGENT_CLI_CREDENTIAL_STORE=file` for login, probes, launch and
  logout. The pinned CLI stores refreshable credentials at owner-only
  `<account-home>/.cursor/auth.json`; Cuckoding does not read, copy, log or place
  them in argv/environment. Task config and compatibility directories remain
  per-run. Fixed shared sandbox/MCP files are checked against expected contents
  and unsafe paths fail closed.
- Claude Code has a reusable reviewed helper; OpenCode and Custom Agent remain
  setup-only and cannot be advertised as working reusable launch adapters.
- Saved-agent cards group assigned roles; legacy unbound roles have an explicit
  selector. A board upgrade matches stable connection keys and compatible
  executable/helper settings, never names. A queued binding is a separate event.
- Deterministic regression tests cover profile reuse across two project-shaped
  runs, distinct accounts, invalid/symlink paths, revoked probes, changed shared
  MCP files, separate task settings and historical snapshot preservation.
- Root account cards show the affected saved-agent count and current project,
  board and role assignments before a confirmed shared-sign-in disconnect.
  Linked cards continue to point to the one root instead of offering duplicate
  login or logout controls. Cuckoding never silently logs out an idle account.
- Real CLI status checks on 2026-09-20 at 18:05 UTC returned sign-in required for
  both existing app-owned accounts. A later Cursor login exposed that an
  isolated `HOME` cannot resolve the macOS default keychain; the browser step
  succeeded but credential persistence failed. Cursor now uses its native
  account-owned file store instead. On 2026-09-21, after a development-server
  restart, the installed Codex CLI reported a ChatGPT login and the installed
  Cursor CLI reported authenticated under their saved app-owned profiles.
  A real Codex invocation with the run-owned `HOME` then failed to find the
  default Keychain; the Codex status check was a false positive for isolated
  execution. The same isolated status with the corrected file-store mode reports
  sign-in required. Verify fresh sign-in, authenticated two-project use, token
  refresh/restart and concurrent provider behavior before closing task 1018.
- On 2026-09-21 at 19:52 UTC, read-only isolated-profile preflight found a
  private Codex file-store credential by metadata only. The installed Codex CLI
  reported ChatGPT sign-in with `CODEX_HOME` set to that app-owned profile,
  file-store mode selected, and a scrubbed explicit environment. The installed
  Cursor CLI reported authenticated with its app-owned `HOME`, config paths,
  native file store, and a scrubbed explicit environment. No credential value,
  provider task, or personal CLI profile was read. These checks establish
  current CLI status, not authenticated cross-project execution or refresh.
- The confirmed disconnect control is implemented and regression-tested. It is
  a provider-scoped logout, not destructive profile-directory deletion, and it
  never touches personal profiles. Real post-login revocation evidence remains open.
- Browser acceptance verifies both root sign-in commands remain complete,
  read-only fields with adjacent copy controls and polite copied-status feedback.
  At a 320 px viewport the page has no horizontal overflow and retains every
  runtime, model, provider-sign-in, edit, copy, and authorization-check control.

Official Codex documentation describes cached login reuse and file/keyring
storage; Cuckoding uses the documented file store because keyring discovery
fails under the isolated run home:
[Authentication](https://learn.chatgpt.com/docs/auth).
