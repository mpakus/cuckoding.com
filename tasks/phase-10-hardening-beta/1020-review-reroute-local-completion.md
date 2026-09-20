---
status: complete
owner: codex
started_at: 2026-09-20
completed_at: 2026-09-20
worklog: worklog/2026-09-20-1020-review-reroute-local-completion.md
---

# 1020 — Route review findings and complete locally

- [x] Review emits bounded, host-validated structured findings with explicit Specifications or Coding routes.
- [x] Blocking findings create durable retry attempts and rerun the required downstream stages within the workflow attempt budget.
- [x] Findings and retry history remain visible in the run timeline; passing Review reaches human choice.
- [x] A human can complete a reviewed run locally without any push or pull-request handoff.
- [x] Local completion is explicit, audited, accessible without drag, and preserves the feature branch, worktree, and evidence.
- [x] Focused workflow, transition, LiveView, security, and full quality checks pass; docs describe shipped behavior only.
