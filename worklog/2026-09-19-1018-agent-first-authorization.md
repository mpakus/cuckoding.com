# 1018 — Agent-first authorization

## Scope and acceptance

Authorize a saved machine-wide agent once, select it across projects and roles,
automatically check unique connections at start, and reconnect only when needed.
Keep execution configuration separate and preserve existing board tasks
and historical snapshots. Full acceptance is in task 1018.

Preserved completed task 1017 as local commit `9ca4879`; new work is on
`feature/1018-agent-first-authorization`. Unrelated `icon.png` remains untouched.
Git index/ref writes required sandbox escalation. No push/merge in the initial
documentation tranche; the September 20 continuation requests a local merge.

## Inspection and skills

- Ponytail 4.10.0 full (MIT), architecture, adapter, security-review, LiveView,
  workflow, quality-gates: reuse the catalog, document the auth/state boundary
  before implementation, do not replace credential reuse with broad home sharing.
- OpenAI Docs: fetched official authentication documentation. It establishes
  cached login and credential-store modes, not cross-home credential reuse.
- Read AgentRuntime, GuidedRun setup collection, run-page rendering, Codex and
  Cursor adapter setup, current product/configuration/architecture/security docs,
  and ADR-024. Existing run setup enumerates roles; Codex account login and run
  probes select different homes; Cursor isolates HOME/config/compatibility dirs.
- Memory quick lookup found no relevant authentication implementation guidance.
- RTK proxy used for exact source/instruction reads. No credentials, Keychain
  entries, auth files, or provider sessions were read or changed.

## September 19 specification tranche / historical handoff

Documented the accepted target flow and implementation order, including a
reviewed legacy-board upgrade instead of telling users to recreate boards.
Current runtime behavior is unchanged. Credential-only reuse remains the
default boundary. Asked whether broader shared app-owned profile/session state
is acceptable; no such authority is inferred from shared-credential reuse.

Before changing storage or running authenticated acceptance, resolve the
provider-specific credential-only mechanism (or receive the explicit shared
profile decision). Do not claim authorize-once works from saved metadata or
mocked probe tests. Task remains incomplete.

Initial documentation checks:

- `rtk git diff --check` — passed.
- `rtk proxy ruby -e ...` — checked task, worklog, and flow existence plus their
  relative Markdown targets; passed. Proxy preserves exact validation output.
- No product tests claimed for the initial specification-only tranche.

## 2026-09-20 implementation continuation

User explicitly selected shared app-owned agent profiles across projects and
requested merging completed work to main. This supersedes the earlier
credential-only default, not the prohibition on personal/global CLI homes.
Acceptance: stable per-account sign-in/probe/launch paths, separate per-run
permissions, global management, grouped roles, explicit legacy bindings,
regression/security/UI checks, then merge. No credentials are copied or printed.

XERJ localhost:9200 is unavailable; source fallback inspected the pinned
vibe-kanban Codex executor (Apache-2.0) for home selection versus launch
configuration. Installed Codex 0.146.0 help confirms --ignore-user-config;
installed Cursor source resolves auth from HOME and config from CURSOR_CONFIG_DIR.
RTK proxy is used for exact reads and unfiltered verification output.

Reference: vibe-kanban commit `735654971bd396aa97b65166955678e4c34f8bf8`,
`crates/executors/src/executors/codex.rs:14-26,35-46` (Apache-2.0): separate home
selection from launch configuration. No source copied; Cuckoding excludes
personal-home fallback and keeps execution permissions/instructions run-owned.

### Delivered

- Reused the existing provider account catalog for the independent Agents page,
  shared Codex/Cursor profiles, audited settings/status changes, automatic unique
  account checks and grouped role cards. No dependency or schema migration.
- Explicit board upgrades and queued-run binding events preserve tasks and past
  snapshots; compatibility checks reject runtime/executable/helper mismatches.
- Symlink checks, private profile directories, fixed Cursor MCP/sandbox config,
  Codex ignored user config/rules and per-run grants retain execution boundaries.
- Updated product, architecture, security, configuration, flow and test docs.
- Applied Ponytail full, architecture, agent-adapter, security-review, LiveView,
  workflow, quality-gates, OpenAI Docs, accessibility and UX-writing guidance.

### Verification

- `rtk env -u CR_PAT mix quality` — exit 0: formatter, warnings-as-errors compile,
  254 tests and 10 properties (zero failures), Credo (3,199 functions, no issues),
  Sobelow and Hex audit (no advisories). Expected crash-fixture logs are not
  failing tests. Earlier focused tests exposed nested audit transactions; fixed
  shared transaction ownership and reran successfully. Credo nesting fixed.
- `rtk env -u CR_PAT mix assets.build` — exit 0, Tailwind and esbuild succeeded.
- `rtk git diff --check` — passed again after final documentation edits.
- `rtk env -u CR_PAT mix format --check-formatted` — exit 0 after module-doc
  corrections; initial sandbox attempt could not open Mix's local PubSub socket,
  so verification used the approved escalation (not an application failure).
- `rtk proxy env -u CR_PAT PHX_SERVER=true mix phx.server` — local server running
  on loopback port 4000; health endpoint reports database/PubSub/endpoint OK.
  Proxy preserves streaming output. Corrected development startup instructions
  because runtime configuration requires PHX_SERVER explicitly.
- Browser: Agents page renders at desktop and 320px; document width equals
  viewport width at 320px. Native keyboard Enter opens Edit Speculator. Async
  checks show disabled checking state and then observed status/UTC check time.
  Both real installed CLIs report sign-in required for these saved profiles.
  No provider task was launched. A later keyboard/copy check was not completed
  because browser automation timed out; viewport override was reset.
- LiveView tests cover independent catalog creation/editing and live persisted
  status. Deterministic runtime tests cover reuse, two-account separation,
  role settings, simulated revocation, stale probes, unsafe paths/MCP and legacy
  history preservation. These are not real authenticated-provider evidence.

### Remaining acceptance / handoff

Sign in once to each app-owned profile in Agents, then verify authenticated runs
in two projects, restart/refresh and concurrent provider behavior. Task 1018 stays
in progress until that evidence exists. No clean-machine native packaging or
release certification claimed. Detailed project impact lists and revoke/delete
controls are follow-ups. Personal CLI homes and unrelated `icon.png` are untouched.
Local merge to main is requested; no remote push is part of this continuation.

## 2026-09-20 lifecycle continuation

Continued on `feature/1018-real-provider-acceptance` after task 1020 merged to
local `main`. Acceptance for this tranche: show the full current project/role
impact of one shared provider identity, require explicit confirmation before
disconnecting it, preserve running/history state, and record a value-free event.
The provider session otherwise has no Cuckoding TTL and persists until provider
expiry/revocation or an explicit disconnect.

XERJ remained unreachable at `http://localhost:9200`; direct source inspection
reused the existing provider-account, app-owned profile, adapter probe, EventStore,
and LiveView patterns. Installed `codex logout --help` and `cursor-agent logout
--help` confirmed native scoped logout commands. No dependency or migration was
added.

### Delivered

- Root cards aggregate linked saved agents and current project, board, and role
  assignments. Linked cards still point to the root and never duplicate login or
  logout controls.
- A confirmed asynchronous **Disconnect shared sign-in** action runs only the
  provider CLI with the app-owned profile environment. It records the request
  before the external action and `provider.authorization_disconnected` after success, changes the root status to
  authorization-required, and therefore blocks new linked launches. Existing
  processes and immutable snapshots are untouched; profile directories and
  personal CLI homes are not deleted.
- UI copy states the truthful retention contract: Cuckoding has no authorization
  expiry timer and cannot promise years because the provider controls expiry.

### Real-provider evidence

At 2026-09-20 18:05 UTC, the installed pinned Codex and Cursor probes both
returned `authentication_required` for the existing app-owned profiles. The
check selected only non-secret account fields, did not inspect token files, and
launched no paid provider task. Status checks durably recorded their normal
value-free audit events. Authenticated two-project, refresh/restart, concurrent,
and real post-revocation checks remain open, so task 1018 stays in progress.

### Verification in progress

- `rtk env -u CR_PAT mix test test/cuckoding/shared_agent_profile_test.exs test/cuckoding_web/agent_settings_live_test.exs`
  — 6 tests, zero failures. Covers impact aggregation, scoped logout argv/env,
  propagated status, audit event, confirmation copy, and linked-agent counts.

### Final verification for this tranche

- `rtk env -u CR_PAT mix quality` — exit 0 on final run: formatter,
  warnings-as-errors compilation, 265 tests and 10 properties with zero failures,
  Credo over 203 files/3,279 functions with no issues, Sobelow clean, and Hex
  audit with no advisories. A prior full rerun hit the existing concurrent SQLite
  property's transient `database is locked`; the same property and seed passed
  alone, changed-area tests passed, and the final complete gate passed.
- `rtk env -u CR_PAT mix assets.build` — exit 0; Tailwind and esbuild completed.
- `rtk git diff --check` — passed.
- Live browser check at `/settings/agents` rendered the no-TTL explanation,
  one impact section per root account, copyable commands, sign-in status, model
  selection, and no duplicate login cards. Both current real profiles still say
  sign-in required, so the disconnect control correctly remains hidden until a
  profile is connected.
- A follow-up real browser check at 18:16 UTC re-probed both saved profiles;
  each still returned sign-in required. Both adjacent **Copy** controls changed
  to **Copied** and announced `Command copied to clipboard.` through the live
  status region. At an exact 320×844 viewport, `innerWidth`, document width, and
  body width were all 320 px; every add/edit/model/sign-in/copy/check control
  remained in the accessibility tree. The temporary viewport override was reset.
- Scoped changed-line security review found no credential value, token content,
  private key, password assignment, provider output persistence, personal-home
  fallback, or unconfirmed destructive action. Provider command output is discarded.

## 2026-09-20 Cursor Keychain persistence fix

The real Cursor browser authorization completed, but the CLI could not save its
login because the approved app-owned `HOME` has no macOS default keychain. A
read-only check reproduced that boundary: `security default-keychain -d user`
succeeded under the personal HOME and failed under an isolated HOME; setting
`CFFIXED_USER_HOME` did not change the result. No keychain item was read,
deleted, reset, or changed.

XERJ remained unreachable. Direct inspection of the installed pinned Cursor CLI
`2026.09.15-d2fe57e` found its supported
`AGENT_CLI_CREDENTIAL_STORE=file` mode in `src/utils/credential-store.ts` and
the provider implementation in `cli-credentials/dist/index.js`. On macOS that
mode stores refreshable credentials at `~/.cursor/auth.json`, creates the parent
with `0700`, and writes the file with `0600`. No vendor code was copied.

The adapter now selects that mode for login, probes, execution and logout while
retaining the app-owned HOME, run-owned task configuration, fixed empty MCP and
sandbox files, plugin rejection, and personal-home prohibition. Cuckoding does
not read, copy, serialize, display or inject credential values. The browser
login must be repeated before authenticated two-project/restart/concurrency
acceptance can close task 1018.

Verification:

- `rtk env -u CR_PAT mix test test/cuckoding/adapters/cursor_agent_test.exs test/cuckoding/shared_agent_profile_test.exs test/cuckoding_web/live/agent_settings_live_test.exs`
  — 12 tests, zero failures. Login, probe, launch and logout all select the same
  persistent credential mode while preserving account/run path separation.
- Real `cursor-agent status --format json` under the corrected app-owned
  environment returned unauthenticated without a Keychain prompt; no token or
  personal provider state was read.
- `rtk env -u CR_PAT mix quality` — exit 0: 265 tests and 10 properties, formatter,
  warnings-as-errors compile, Credo, Sobelow and dependency audit all passed.
  The two logged fixture crashes are the expected supervisor-restart test.
- `rtk env -u CR_PAT mix assets.build` and `rtk git diff --check` — passed.
- Live browser verification after a server restart showed the Cursor command
  beginning with `AGENT_CLI_CREDENTIAL_STORE='file'`; the personal HOME and
  Keychain are absent from the command.
