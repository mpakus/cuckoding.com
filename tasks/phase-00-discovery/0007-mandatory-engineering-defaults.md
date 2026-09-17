# 0007 — Mandatory engineering defaults

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0007-mandatory-engineering-defaults.md
```

## Objective

Make RTK, Ponytail minimalism, focused coverage, and proportionate quality gates explicit repository-wide defaults without turning optional product plugins into core runtime dependencies.

## Acceptance criteria

- [x] Root rules require RTK for every shell command and Ponytail for every repository change or review.
- [x] Minimalism requires the smallest coherent root-cause solution and cannot weaken safety, durability, accessibility, observability, migrations, or accepted behavior.
- [x] Behavioral changes require focused runnable regression coverage; documentation-only changes require proportionate structural validation.
- [x] Relevant quality gates and exact results must be recorded before completion.
- [x] Repository skill and product-plugin documentation distinguish mandatory contributor practice from optional runtime integration.
- [x] Active reference-coding documentation points to a current isolated XERJ project corpus.
- [x] Updated skill metadata and documentation pass structural validation.
