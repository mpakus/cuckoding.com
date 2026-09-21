# MVP Boundary and Positioning

**Decision date:** 2026-09-17; approved by the sole stakeholder  
**Review date:** 2026-10-01, after the first user interviews  
**Scope:** task 0001; implementation-status corrections for task 1004 on 2026-09-21

## Launch contract

The MVP is a single-user, local-first macOS application for Apple Silicon. A menubar shell starts a Phoenix release bound to loopback and opens its LiveView UI in the default browser. Agent and project commands run as supervised host processes in per-run Git worktrees. This is a trusted-host model, not a sandbox.

The implemented launch adapters are:

1. **Claude Code**
2. **Codex**
3. **Cursor Agent**

Their fixture conformance does not establish real-provider beta acceptance;
authenticated default workflows and shared-profile recovery remain open gates
in [PLAN.md](PLAN.md). OpenCode and Custom Agent can be saved during setup but
cannot launch tasks. The first distribution supports one local user and one
Mac. It must keep multiple boards and runs isolated and durable across
application restart and sleep/wake.

The MVP includes durable workflows, approvals, worktrees, process supervision, evidence and review artifacts, resource and cost attribution, project-scoped knowledge, plugin contracts, and a host-side branch/PR handoff. It does not include container or VM isolation, hosted execution, team synchronization, autonomous merge/deploy, mobile or Windows clients, or x86 macOS packaging.

## Positioning

**For developers running two or more coding agents on one Mac, Cuckoding is the local workflow control plane that makes long-running work recoverable, reviewable, and attributable across providers. Unlike a provider-native agent UI or a lightweight task launcher, it persists workflow truth outside agent sessions, reconciles sleep and failure, makes trust-boundary approvals explicit, and turns evidence into reviewed project knowledge.**

The product should not compete on chat, code editing, or the number of simultaneous agents. Those capabilities are already available in provider-native tools. It should compete on orchestration correctness and trust.

## Competitive scan

| Product or capability | What it already solves | Gap that informs Cuckoding |
| --- | --- | --- |
| Claude Code | Native subagents, agent teams, worktrees, permissions, and resumable local sessions | Provider-specific; its permission model also documents that Bash subprocesses require OS sandboxing for filesystem enforcement |
| OpenAI Codex | Durable goal-oriented coding work and explicit multi-agent configuration | Provider-specific; Cuckoding must preserve a provider-neutral durable workflow and evidence model |
| Cursor | Remote background agents in isolated Ubuntu machines, branches, and parallel work | Cloud/GitHub execution with documented internet and data-exfiltration risk; different trust and locality model |
| Agetor | Local-first multi-agent worktrees, approvals, persistent runs, and SQLite | Explicitly gives agents full host privileges and no sandbox; validates demand but not the security/recovery wedge |
| Vibe Kanban | Worktree-backed task execution, approval UI, cleanup hooks, and multiple coding agents | Strong task launcher; Cuckoding adds typed gates, durable recovery, sleep reconciliation, and reviewed knowledge provenance |
| Hydra reference design | Process identity, lifecycle, resume, bounded logs, and risk-driven test gates | Confirms that ownership proofs and recovery tests belong in the first implementation, not in later polish |

Reference-code evidence is pinned in `docs/reference-corpus.yml`:

- `agetor@eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a`: `README.md:5-24`, `README.md:75`, `README.md:272-284`, `README.md:383`.
- `vibe-kanban@735654971bd396aa97b65166955678e4c34f8bf8`: `docs/core-features/monitoring-task-execution.mdx:15-28`, `:59-69`.
- `hydra@d8ad56112c2c3acfb2f65f53b6890f30a25c693c`: `PLAN.md:350-375`, `:501-513`, `:598-607`.

## Data classes and defaults

| Data class | Default location | Default retention | Export or telemetry default |
| --- | --- | --- | --- |
| Projects, workflows, runs, events, approvals, policy snapshots, artifact metadata | Local SQLite | No automatic age purge; archive does not delete audit history | Never exported automatically |
| Knowledge content | Project Markdown files; SQLite stores index and provenance | Until revoked or deleted by the user | Project-scoped; global publication requires approval |
| Redacted command and agent output | Owner-only local artifacts with a bounded UI preview; related events in SQLite | No automatic age purge implemented; full redacted artifacts remain until explicit, verified cleanup | Never exported automatically; full-log download is explicit |
| High-frequency CPU/memory samples | Local SQLite | Raw samples eligible after 7 days only when required minute and finished-stage rollups exist; rollups eligible after 30 days | Never exported automatically |
| Provider payload fragments needed for diagnosis | Redacted local JSON where persisted | No automatic age purge implemented | Never exported automatically |
| Secrets | App-managed opaque references in SQLite and values in macOS Keychain; provider-owned Codex/Cursor credentials in owner-only app-owned native file profiles | Provider expiry or explicit revocation controls provider credentials; Cuckoding does not promise a fixed lifetime | Never included in diagnostics or product telemetry |
| Product analytics and crash reports | No automatic outbound collection implemented | Not applicable until an opt-in collector exists | Diagnostics export and update check require explicit actions |

Local operational events and metrics are on because the product cannot recover
or explain a run without them. Cuckoding has no automatic outbound product
telemetry client. Provider runtimes, explicit update checks, and approved VCS
handoff have separate network behavior; Cuckoding does not upload repository
source through product telemetry. Output/artifact retention and participant
disclosure need a reviewed release policy before beta enrollment.

## Product hypotheses

### Name

`Cuckoding` is the current public working name in the repository and on
`cuckoding.com`; it is no longer internal-only. Final name approval remains
pending the planned **2026-10-01** review after 3–5 interviews plus trademark
and domain screening. `Runstead`, `Branchyard`, and `Agent Harbor` remain
unapproved alternatives, not availability claims.

### License

The repository already contains an Apache License 2.0 `LICENSE` and presents
the local core and plugin contracts under it. The earlier instruction not to
add that file is superseded by the repository state. Owner/legal review of the
open-core and paid-module boundary remains a release decision; do not present
that review as completed merely because the file exists.

### Pricing

Test this non-binding hypothesis in interviews:

- Community: free local core, basic adapters, plugin system, and local orchestration.
- Pro: **$20/month or $200/year** for an individual, including signed distribution/updates, advanced workflows and policy packs, and support.
- Teams, post-MVP: **$40/user/month** for synchronization, SSO, centralized audit/budgets, and managed knowledge catalogs.

Core local orchestration, basic adapters, and the plugin system must remain useful without a subscription. The price points deliberately match a familiar developer-tool range; willingness to pay has not yet been validated.

## Interview gate

The sole stakeholder will interview 3–5 developers who currently run at least two coding agents during controlled beta task 1003. Use 30-minute interviews and include at least one independent developer, one small-team lead, and one security-sensitive developer.

Ask each participant to walk through their last multi-agent task, interruptions and recovery, worktree/terminal coordination, evidence needed before merge, security concerns, and current spend. Then test the positioning, launch adapters, public-name candidates, open-core boundary, and pricing without leading them. Record anonymized notes and decisions in a dated worklog; do not put contact details in the repository.

Participant recruitment and calendar details remain outside Git. Task 1003 owns anonymized interview evidence and the 2026-10-01 product-hypothesis review.

## Sources checked

- [Claude Code subagents and worktrees](https://code.claude.com/docs/en/agents)
- [Claude Code permissions and sandbox boundary](https://code.claude.com/docs/en/permissions)
- [Claude Code sessions](https://code.claude.com/docs/en/sessions)
- [OpenAI Codex app: parallel agents and worktrees](https://openai.com/index/introducing-the-codex-app/)
- [OpenAI Agents API: create an agent](https://developers.openai.com/api/reference/typescript/resources/beta/subresources/agents/methods/create)
- [Cursor background agents](https://docs.cursor.com/background-agent)
- [Cursor pricing](https://cursor.com/en-US/pricing)
- [Agetor](https://github.com/alamops/agetor)
- [Vibe Kanban worktree execution](https://github.com/BloopAI/vibe-kanban/blob/main/docs/core-features/monitoring-task-execution.mdx)
- [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.html)
- [OSI license list](https://opensource.org/licenses)
