# MVP Boundary and Positioning

**Decision date:** 2026-09-17  
**Review date:** 2026-10-01, after the first user interviews  
**Scope:** task 0001

## Launch contract

The MVP is a single-user, local-first macOS application for Apple Silicon. A menubar shell starts a Phoenix release bound to loopback and opens its LiveView UI in the default browser. Agent and project commands run as supervised host processes in per-run Git worktrees. This is a trusted-host model, not a sandbox.

The two supported launch adapters are:

1. **Claude Code**
2. **Codex**

Cursor Agent and OpenCode keep stable adapter contracts and test doubles, but they are not launch-supported until their conformance suites pass. The first distribution supports one local user and one Mac. It must keep multiple boards and runs isolated and durable across application restart and sleep/wake.

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
| Projects, workflows, runs, events, approvals, policy snapshots, artifact metadata | Local SQLite | Until the user archives or deletes the owning project; audit facts remain append-only until that action | Never exported automatically |
| Knowledge content | Project Markdown files; SQLite stores index and provenance | Until revoked or deleted by the user | Project-scoped; global publication requires approval |
| Redacted command and agent output | Local database/artifact store | 30 days after run completion, configurable | Never exported automatically |
| High-frequency CPU/memory samples | Local SQLite | Full resolution for 7 days; rollups for 30 days; then removable | Never exported automatically |
| Provider payload fragments needed for diagnosis | Redacted local JSON only | 30 days, configurable | Never exported automatically |
| Secrets | macOS Keychain; SQLite stores opaque references | Until revoked by the user or provider | Never telemetry |
| Product analytics and crash reports | None unless enabled | Defined before opt-in collection ships | **Off by default** |

Local operational events and metrics are on because the product cannot recover or explain a run without them. Outbound telemetry is off. Cuckoding does not upload repository source; provider runtimes remain subject to their own user-selected policies.

## Product hypotheses

### Name

`Cuckoding` remains an internal codename only. A public name is deferred to **2026-10-01**, after 3–5 interviews plus trademark and domain screening. Working candidates are `Runstead`, `Branchyard`, and `Agent Harbor`; none is approved or represented as available.

### License

Use **Apache License 2.0** for the local core and plugin contracts, subject to owner/legal approval by **2026-09-24**. It is OSI-approved, includes an express patent grant, and permits a useful open core. Paid modules can remain proprietary. Do not add a repository `LICENSE` until the decision is approved.

### Pricing

Test this non-binding hypothesis in interviews:

- Community: free local core, basic adapters, plugin system, and local orchestration.
- Pro: **$20/month or $200/year** for an individual, including signed distribution/updates, advanced workflows and policy packs, and support.
- Teams, post-MVP: **$40/user/month** for synchronization, SSO, centralized audit/budgets, and managed knowledge catalogs.

Core local orchestration, basic adapters, and the plugin system must remain useful without a subscription. The price points deliberately match a familiar developer-tool range; willingness to pay has not yet been validated.

## Interview gate

Recruit 3–5 developers who currently run at least two coding agents. Schedule 30-minute interviews before 2026-10-01 and include at least one independent developer, one small-team lead, and one security-sensitive developer.

Ask each participant to walk through their last multi-agent task, interruptions and recovery, worktree/terminal coordination, evidence needed before merge, security concerns, and current spend. Then test the positioning, launch adapters, public-name candidates, open-core boundary, and pricing without leading them. Record anonymized notes and decisions in a dated worklog; do not put contact details in the repository.

Scheduling is a human-owned gate because the repository has no participant list or calendar authority.

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
