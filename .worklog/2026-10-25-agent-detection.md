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

## Research and decisions (in progress)

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
  backpressure gates remain separate and open. Contract being agreed with writers.

## Outcome and next step

In progress: finalize probe contract, implement backend/UI, verify fixture failures
and real local metadata/UI, then update docs, merge/check main and archive writers.
