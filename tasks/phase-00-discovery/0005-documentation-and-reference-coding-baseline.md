# 0005 — Documentation and Reference-Coding Baseline

```yaml
status: done
owner: codex-01a0ad73-9f18-7ad1-8842-e5e0f041d160
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0005-reference-coding-baseline.md
```

## Objective

Audit the complete `docs/` tree, establish local XERJ source and peer-project indices, require reference retrieval before unfamiliar implementation work, and make RTK the default wrapper for repository shell commands.

## Dependencies

- None. This task establishes development-process evidence and does not start product implementation.

## Scope

Inspect every tracked or proposed artifact under `docs/`, report contradictions, broken references, missing controls, and task-plan issues without rewriting product decisions speculatively. Verify the current XERJ installation, run its node on loopback with state outside the indexed trees, index this repository, and clone a small set of license-reviewed open-source projects closest to Cuckoding's architecture into an external reference directory. Index each corpus under a distinct prefix and prove retrieval with file-and-line evidence. Document an RTK-always shell workflow with explicit bypass guidance for commands that require unfiltered output.

## Deliverables

- Complete documentation inventory and findings report.
- Local XERJ project index with a reproducible prefix and state directory.
- Reference-corpus manifest containing repository URLs, pinned revisions, licenses, problem domains, and XERJ prefixes.
- Reference-coding instructions that require retrieval before unfamiliar implementation work and license checks before adaptation.
- RTK-always repository command guidance.
- Worklog containing exact commands, results, limitations, and residual risks.

## Checklist

- [x] Inspect every file under `docs/`, including plans, plugin specifications, task files, worklogs, templates, and non-Markdown assets.
- [x] Separate internal contradictions from decisions that are explicitly deferred.
- [x] Keep XERJ data and cloned references outside the repository and bind the node to loopback only.
- [x] Estimate each index run before execution and record actual outcomes without treating exit code 3 as failure.
- [x] Use distinct XERJ prefixes so project and peer results can be queried independently.
- [x] Record reference licenses and mark copyleft sources as approach-only where applicable.
- [x] Demonstrate at least one project query and one peer-reference query with `path:line` evidence.
- [x] Prefix repository shell commands with `rtk`; use `rtk proxy` only when full, unfiltered output is required.

## Acceptance criteria

- [x] Every artifact under `docs/` appears in the audit inventory or an explicitly documented excluded class.
- [x] XERJ reports the project and selected peer corpora as indexed and returns bounded source passages.
- [x] A future agent can reproduce corpus refreshes and knows when reference retrieval is mandatory.
- [x] Repository guidance consistently states that shell commands use RTK by default.
- [x] No secret, user credential, unrelated repository, or XERJ data directory is added to the corpus.

## Verification and evidence

Record the documentation inventory checks, XERJ version/health, dry-run estimates, index completion lines, corpus revisions/licenses, bounded searches, link checks, and final diff validation in `worklog/2026-09-17-0005-reference-coding-baseline.md`.
