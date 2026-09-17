# Worklog — 0005 Documentation and Reference-Coding Baseline

## Metadata

- Date/time (UTC): 2026-09-17T03:42:37Z
- Task: 0005
- Status: done
- Human/agent owner: codex-01a0ad73-9f18-7ad1-8842-e5e0f041d160
- Branch: `feature/0005-reference-coding-baseline`
- Start revision: `b101eee347e6b19d53209decd7504d1f61a94a85`
- End revision: working tree only; no commit requested
- Environment and relevant tool versions: macOS arm64; XERJ `v1.0.0-rc.74`; RTK `0.49.0`; lexical XERJ node on loopback

## Intended outcome

Audit the entire `docs/` tree, index this repository and a focused licensed reference corpus with XERJ, prove bounded reference retrieval, and document RTK as the default wrapper for repository shell commands.

## Context inspected

- Root `AGENTS.md` and `/Users/mpak/.codex/RTK.md`.
- Required product, architecture, database, flow, security, and execution-environment documents.
- All 50 files under `docs/`: 42 Markdown files, six YAML files, and two Finder metadata files. The 48 substantive artifacts include all core specifications, plugin specifications, repository skills, role prompts, and configuration examples.
- Task protocol, all 49 numbered tasks, worklog templates, plugin overview, XERJ and RTK plugin specifications, and external references were cross-checked for execution consistency.
- Initial Git state: `main` at `b101eee`, one commit ahead of `origin/main`; `AGENTS.md` and `docs/` were untracked. Those files are treated as user-owned and preserved.
- The 13 repository skills and `.cuckoding` examples exist under `docs/`, not at the repository-root paths declared by `README.md` and `AGENTS.md`. This is recorded as a Phase 01 blocker, not silently duplicated.

## Work performed

- Claimed task 0005 and created the scoped task branch.
- Read every substantive file under `docs/`, parsed every YAML artifact, inspected the two `.DS_Store` files as excluded OS metadata, and visually inspected the repository-root inspiration image.
- Added `docs/DOCUMENTATION_AUDIT.md` with prioritized findings and an implementation-readiness conclusion.
- Added `docs/REFERENCE_CODING.md` and `docs/reference-corpus.yml` with the retrieve-before-code rule, external storage layout, pinned revisions, licenses, distinct prefixes, reproducible commands, and citation requirements.
- Made RTK-always explicit in `AGENTS.md`, `README.md`, `docs/SKILLS.md`, and the RTK plugin spec. Kept product configuration commands unwrapped so policy validates the underlying command before the optional plugin runs.
- Corrected XERJ documentation to distinguish lexical default retrieval from explicit neural retrieval and to declare loopback transport instead of no network.
- Changed plugin network examples to the explicit `none | loopback | external` vocabulary and added the missing task 0504 dependency on secret-store task 0204.
- Verified that the installed XERJ binary is already the release documented by current upstream instructions, so no redundant overwrite was performed.
- Created external XERJ data/state directories and shallow-cloned three focused peer projects outside this repository. No credentials, unrelated repositories, or XERJ data were added to the corpus.
- Started XERJ with lexical embeddings and authentication disabled on loopback only. Listeners were observed on `127.0.0.1:8080`, `127.0.0.1:8081`, and `127.0.0.1:9200`.
- Dry-ran and indexed the project and all peers. Rebuilt the active project corpus as incremental `cuckoding-project-v2` with `--no-graph`; the earlier v1 project prefix is superseded.
- Proved bounded retrieval against the project and all three peers. XERJ's requested field report was produced with `--dry-run`; no file, issue, branch, or pull request was created.

## Artifacts

- Commits/patches: working tree only; no commit requested. Primary artifacts are `docs/DOCUMENTATION_AUDIT.md`, `docs/REFERENCE_CODING.md`, and `docs/reference-corpus.yml`.
- Migrations: none.
- Logs/reports/screenshots: XERJ terminal evidence is summarized below; no raw authentication material is persisted.
- Configuration or policy hashes: peer revisions are pinned below; project base revision is `b101eee347e6b19d53209decd7504d1f61a94a85` with the working tree included.

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk git status --short --branch` | pass | Baseline captured; existing untracked files preserved. |
| `rtk xerj --version` | pass | `xerj v1.0.0-rc.74`. |
| `rtk --version` | pass | `rtk 0.49.0`. |
| `rtk lsof -nP -iTCP -sTCP:LISTEN` | pass | XERJ listeners are loopback-only on ports 8080, 8081, and 9200. |
| Full `docs/` inventory | pass | 50 files: 42 Markdown, six YAML, two excluded `.DS_Store`; 48 substantive artifacts. |
| Ruby `YAML.safe_load_file` across `docs/**/*.yml` | pass | All six YAML files parsed after quoting the manifest date scalar. |
| Required-heading check across numbered tasks | pass | All 49 numbered task files contain objective, dependencies, scope, deliverables, acceptance, and verification sections. |
| `rtk xerj autoindex ... --dry-run --no-graph --prefix cuckoding-project-v2 ...` | pass | 87 files discovered; 84 files planned; measured client extraction floor 0.0–0.0 s; server work explicitly excluded. |
| `rtk xerj autoindex ... --no-graph --prefix cuckoding-project-v2 ... --yes` | pass | Initial generation: 84 files, 166 records in 16.3 s. Recorded reconciliation: exit 3, `completed-with-junk`; 84 files, 170 records, generation 2, 15.4 s. Three non-source artifacts were explicitly junked; this docs-only pack has zero code files. |
| Agetor index | pass | `ref-agetor-v1`: 768 files, 6,550 records, 47.1 s; 579/579 code files indexed. |
| Vibe Kanban index | pass | `ref-vibe-kanban-v1`: 1,491 files, 12,890 records, 123.4 s; 1,161/1,161 code files indexed. |
| Hydra index | pass | `ref-hydra-v1`: 204 files, 1,900 records, 31.5 s; 158/158 code files indexed. |
| Pinned revision and license checks | pass | Agetor `eb74ab5…` MIT; Vibe Kanban `7356549…` Apache-2.0; Hydra `d8ad561…` MIT. License files were inspected at each revision. |
| `rtk xerj search --prefix cuckoding-project-v2 ...` | pass | Returned bounded project passages, including task 0005 and durable event foundation task 0102; corresponding RTK/reference rules are at `AGENTS.md:36-37`. |
| `rtk xerj def --prefix ref-agetor-v1 API_TOKEN` | pass | `src/bun/api-config.ts:24`: per-launch random loopback token with environment override. |
| `rtk xerj def --prefix ref-vibe-kanban-v1 WorktreeManager` | pass | `crates/worktree-manager/src/worktree_manager.rs:52`: central worktree lifecycle entry point; Cuckoding retains stricter ownership checks. |
| `rtk xerj def --prefix ref-hydra-v1 hydrateWorkspaceAgents` | pass | `electron/agents/AgentManager.ts:300`: persisted workspace/provider-session hydration entry point. |
| `rtk xerj feedback --dry-run ...` | pass | Complete field report rendered; no write, issue, branch, or PR. |

## Telemetry and operational evidence

XERJ-reported wall times and counts are recorded above. They are measurements from this machine. Dry-run estimates cover client extraction only and are not relabeled as whole-run predictions. The `gain` audit was reachable on the native loopback listener, but its aggregate includes autoindex-internal searches and is not used as product-value evidence.

## Decisions and deviations

- Created a dedicated Phase 00 process-baseline task instead of claiming Phase 08 task 0803, which is gated product implementation with broader acceptance criteria.
- Use lexical mode for exact symbol and API retrieval unless a later measured need justifies a neural reindex.
- Reuse the installed current XERJ binary rather than download and overwrite it with the same release.
- Use `--no-graph` for the active project journal so additions, changes, moves, and removals reconcile incrementally. Pinned peer snapshots retain their v1 prefixes; a changed peer revision gets a new prefix.
- Treat reference code as untrusted evidence. Record `path:line`, pinned revision, license, the adapted idea, and Cuckoding-specific constraints; do not copy an implementation blindly.

## Risks and blockers

- The documentation and task pack remains untracked, so the branch does not preserve it until the user commits or otherwise records it.
- Root placement of `docs/.agents/` and `docs/.cuckoding/` is unresolved and blocks Phase 01. Choose promotion or an intentional contract change; do not create duplicate sources of truth.
- The generic GitHub MCP example uses an unpinned npm package and must remain disabled until task 0803 chooses a maintained, exactly pinned implementation with integrity and conformance evidence.
- Recovery tasks 0203 and 1002 still need a deterministic fixture matrix and denominator for the stated 95% target.
- Forty-one doubled periods/repeated task-objective sentences remain low-priority editorial debt.
- XERJ is running as a foreground local process for this session, not as a persistent login service. Restart it with the documented RTK command when needed.

## Handoff

Before Phase 01, resolve the hidden-directory placement finding. Before unfamiliar implementation work, start the local XERJ node, follow `docs/REFERENCE_CODING.md`, search `cuckoding-project-v2` and the relevant peer prefix, and cite the inspected source in that task's worklog. Do not delete the external state or reference checkouts unless intentionally rebuilding the corpus.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
