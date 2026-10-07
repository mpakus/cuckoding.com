# R020d — Bounded Codex model-access check

Status: complete, integrated into local main, 2026-10-07. Branch: `feature/r020d-model-access-check`.
Parent: [R020](R020-codex-connection.md).

- [x] Select a validated fresh catalog model and explicitly consent to one fixed diagnostic prompt that can consume provider usage.
- [x] Persist command/snapshot before launch; bind account/catalog/executable identity and reject stale or overlapping work.
- [x] Use a private scratch directory and verified restrictive runtime configuration; reject unsupported effective grants before a turn.
- [x] Require matching thread/turn completion and exact public response, retain requested/observed model separately, reject tool activity and model drift, discard all raw/hidden output.
- [x] Bound duration/output, interrupt on cancellation and clean the owned group; never replay interrupted generation.
- [x] Show progress/model/elapsed/cancel and durable reconnectable results, with authentication, catalog and tested access kept distinct.
- [x] Add focused parser, authority, canary, recovery, UI and packaged checks; leave real signed-in execution open unless actually exercised.
- [x] Update docs, AGENTS and README; merge local main and delete this merged branch.
