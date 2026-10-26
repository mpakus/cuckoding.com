# BOSS-006 — agent detection and capability probes

## Scope and baseline

- Baseline clean local main `4ae914e`; root branch `codex/boss-agent-detection`.
  Previous application suite 159 passed / 1 Linux-only skipped. Effective
  Elixir 1.20.3 compiled for/running OTP 28 rechecked this turn.
- User requested continuation. Scope: explicit Detect Agents action for Codex and
  Claude Code, version/path, local CLI auth report, advertised capabilities and
  safe official setup/sign-in guidance. No model run, role persistence or task
  execution controls until runner/adapters exist. No automatic paid probes.
- RTK/Ponytail and incremental/frontend skills used. Two isolated writer worktrees:
  backend owns detector/probe/tests; UI owns AgentsLive/Home navigation/tests.
  Root owns application/router/shared documentation and integration; independent
  reviewer checks source patterns and finished implementation.
- Read BOSS_PLAN sections 7/9/task006, task plan/status, latest worklog and AGENTS.
  Source specs and existing data remain unchanged. No new dependency planned.

## Research and decisions

- xerj `detect agent cli version capability` returned AO version/auth selection
  patterns; `detectCodex auth status` was mostly unrelated. Weak hits are leads,
  not implementation proof; reviewer is reading actual pinned detection/tests.
- Installed CLI metadata inspected only: `codex --version`, `codex --help`,
  `codex exec --help`, `codex login --help`, `claude --version`, `claude --help`,
  `claude auth --help`, `claude auth status --help`, from `/` with 10 s limit.
  Codex 0.146.0 and Claude Code 2.1.142 are native Mach-O executables on this host.
  Their help advertises structured output/streaming/resume and local auth status.
- Official CLI docs consulted after local help: Codex CLI reference redirects to
  `https://learn.chatgpt.com/docs/developer-commands?surface=cli`; Claude reference
  `https://code.claude.com/docs/en/cli-reference` describes auth status JSON.
  Newer online flags do not prove support in an installed older binary.
- Distinguish discovery, recognized identity/version, help-advertised features and
  CLI-reported auth from verified model usability. Unknown output stays unknown.
  Never read auth files or retain/reflect raw status output, key suffixes or account
  data. No `doctor` (may spawn integrations), login, update or model command.
- Use a bounded metadata process path only; production runner descendant/EOF/
  backpressure gates remain separate and open. Contract fixed below.

## Reference evidence and contract

- Agetor MIT `fbd68603afef778a618a94ca88e0c00997956afd`,
  `src/bun/agent-status.ts:89/430`, `agent-status.test.ts:44`: short version probes
  and separate auth status. Reject its permissive available=true on /bin/echo,
  credential/account-file discovery and tmux requirement.
- Agent Orchestrator Apache-2.0 `7193eff4e08f1481944845ee058fe6fd18930b6d`,
  `backend/internal/adapters/agent/claudecode/auth.go:372`, `auth_test.go:139`:
  loggedIn=true is configured, never authorized. `agent/codex/codex.go:320` and
  `codex_test.go:73` inform local status parsing. Do not adopt credential-file or
  network fallback ladders. Pinned SHAs rechecked; no code copied.
- Reviewer follow-up xerj queries `probeVersion`, `codexLoginMethod`,
  `claudeAuthReportFromOutput` found useful concrete symbols after broad misses.
- Final detector API: `scan/0` returns two fixed maps or busy/cancelled/unavailable.
  Row fields id/name/path/version/probe_status/auth_status/capabilities/errors.
  probe_status: ok/missing/unsupported/failed; auth: configured/not_configured/unknown.
  Six capabilities use advertised/not_advertised/unknown; usage_reporting stays
  unknown. Errors carry only fixed stage/reason atoms, never raw diagnostics.
- One GenServer owns sequential probes, requester monitor, per-probe 5 s / 64 KiB
  retained output and 30 s scan deadline. Fresh exclusive scratch cwd outside any
  project. Direct-child cleanup follows current FolderPicker pattern; wrapper
  descendants, independent stream EOF and transport memory bounds are not claimed.
- UI contract: explicit action (no mount probes), previous results retained on
  rescan failure with clear notice, timestamp, official guidance and no editable
  executable paths. Use frontend UI and real-browser verification skills;
  existing CUA is sufficient, no extra integration installed.

## Implementation/review progress

- Protected route root commit `afa77eb`; UI `e231010` integrated after independent
  read-only review. Five new Agents tests + five existing project/picker UI tests
  passed; no probe on anonymous/disconnected mount, explicit one-at-a-time action,
  fixed errors, retained prior results, timestamps and safe official guidance.
  Compile warnings/format/diff checks passed in UI worktree.
- UI reference query `agent detect version authentication capabilities installed cli`
  led to AO `frontend/src/renderer/lib/agent-select-options.ts:108`, tests and
  `CreateProjectAgentSheet.test.ts:199` (same pinned SHA). Adopt configured/unverified
  distinction; reject ranking/launch controls before execution exists.
- Backend extra xerj `runProbe agent discovery timeout executable version` → Agetor
  `src/bun/agent-discovery.ts:29/170`, `agent-discovery.test.ts` and
  `agent-status.ts:100` (same pinned MIT SHA). Adopt bounded argv probes and actual
  failure fixtures, reject app-server RPC/model calls/install and unbounded output.
  Elixir 1.20.3 `lib/gen_server.ex:817` documents format_status/1 redaction.
- Backend first 13-test RED (module absent) became GREEN with metadata/parser and
  direct Port owner modules. Additional RED cases caught prose flags/subcommands,
  duplicate loggedIn fields and default0755 scratch permissions. Fixes constrain
  evidence to declarations, use ordered JSON fields and make scratch0700.
  Reviewer also required streaming format evidence to stay within its own option,
  not unrelated prose; fixed with negative and wrapped-declaration fixtures.
- Independent source review has no remaining blockers within direct-child scope.
  Global scan/timer identity, caller cancellation and redacted format_status were
  checked; focused results and root/browser evidence follow.

## Verification and limits

- Backend commit `7d6376c`: 17 focused tests passed (2.2 s), compile warnings,
  format and diff checks passed. UI commit `e231010`: 10 focused tests passed.
  Parent integrated both sequentially and added Detector to Application (`e1f2566`).
- Root `rtk proxy asdf exec mix test`: 181 passed / 1 Linux-only skipped,
  seed 198201 (7.3 s). `rtk proxy asdf exec mix compile --warnings-as-errors`,
  `rtk proxy asdf exec mix format --check-formatted`,
  `rtk proxy asdf exec mix assets.deploy` all passed.
- Metadata RED/GREEN evidence: malformed/unrelated identity, conflicting duplicate
  JSON booleans, flags/subcommands only in prose, unrelated stream-json prose,
  wrapped option declaration, non-executable path and default0755 scratch mode.
  Lifecycle fixtures verify owned child stop on timeout/output/caller down/orderly
  supervisor stop, busy/repeat-after-cancel, scan deadline and stale port messages.
  `:sys.get_status` and abnormal shutdown logs exclude the private output sentinel.
- Actual browser on isolated fresh data/owned loopback server: Home → Agents via
  keyboard opens two Not checked sections without probing. Keyboard activation of
  Detect shows disabled/busy status, then Codex 0.146.0 and Claude Code 2.1.142.
  Both report credentials configured; five capabilities advertised and usage
  Unknown. No raw auth/account output appeared. This is local CLI metadata only,
  not an authentication validation or provider smoke run.
- Real DOM/AX confirms one h1, two h2 and nested capability h3 headings; Tab order
  Projects → Detect → Codex setup → Claude setup. No page overflow at
  320/768/1024/1440 px. Reload resets to Not checked with no timestamp and no
  automatic scan. Return Home preserves read-only repository folder input.
- Screenshots saved without modifying image bytes, using their actual JPEG format:
  `boss-agents-before.jpg`, `boss-agents-mobile.jpg`, `boss-agents.jpg` in
  `/Users/mpak/.codex/visualizations/2026/10/25/01a173ec-2089-7ff3-88a7-142cfa5d8f78/`.
  An initial PNG-signature assertion detected the tool's JPEG output; renamed only
  these new artifacts. Server cleanup had already succeeded and was reverified.
- Existing IAB MutationObserver error appeared without a source URL, as in 003b
  and 005. No new app error was observed; no clean-console or cross-browser claim.
  Linux desktop, CLI wrappers/descendants, untrappable VM death and provider
  auth/quota/model behavior remain unverified. No paid/model command was run.
- One-use browser token stayed out of URLs/logs and was removed after form use.
  Owned browser tab closed, viewport reset; verified exact server command/PGID,
  SIGTERM stopped it, port closed, then removed only the exclusive scratch root.
- Updated AGENTS, README, AGENT_DETECTION, RESEARCH, plan/status and daily worklog.
  No dependency, schema, source-spec or project-data changes.

## Outcome and next step

BOSS-006 implementation and root verification complete. Pending local-main merge,
combined checks, writer archival and deletion of merged temporary branches.
Next: BOSS-007 production runner. Independent EOF, bounded transport/backpressure,
descendant cleanup and recovery ownership must be resolved before agent execution.
