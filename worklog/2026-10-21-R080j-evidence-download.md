# R080j — Public evidence downloads

Claimed on `feature/r080j-evidence-download`, starting from local main `2978b32`.
The user file `Untitled.md.age` is untouched. RTK proxy preserves exact source,
test, build and Git output. Ponytail full reuses the existing evidence DTO and
authenticated download boundary, without a new persistence model or dependency.

Delivered **Download evidence · JSON** in the task inspector's existing actions.
The link retains the selected execution and optional older-page attempt cursor;
the latest page is observed at download time. The domain resolves all four scope
IDs and any cursor through the same task/execution, then serializes only the
existing public projection. Exports carry a version, UTC date, scope, frozen
criteria, 20 attempts/overflow flag and a retained-evidence notice. More than
2 MiB is refused without truncation. The controller requires a current session,
uses the existing loopback/origin/no-store boundary and a UUID-based attachment.
No raw native path/file, request/context, thought frame or claim token is exported.
Reading adds no command/event or authority; final review/recovery stay in Inspect.

Verification:
- Three new focused checks failed before implementation (missing route/link).
- Full `rtk proxy mix quality`: **442 tests passed**, format/compile with warnings
  as errors, strict Credo, Sobelow and both dependency audits clean. Existing
  generated-lockfile quoted-keyword warnings remain. Earlier runs found a missing
  alias and an incorrect test expectation for JSON's Content-Type; both corrected
  before the final pass. No analysis suppression was added.
- Tests cover attachment/content type/no-store, exact public criteria/bindings,
  private-field exclusion, 20/3-attempt pages, execution/link pinning, dirty text,
  no writes, missing/expired sessions, foreign scope/cursor, malformed cursor and
  over-limit refusal. The first oversized fixture tried to rewrite an immutable
  receipt and was correctly rejected by SQLite; the final fixture inserts a new
  terminal attempt instead. Production triggers were not changed.
- Mutation removed the cursor's battle/task predicate: the foreign-cursor test
  failed with HTTP 200 instead of 404, exit 2. Source was restored before final
  quality/build. No app was running during the mutation.
- `rtk proxy bin/dev.build` passed production compilation and strict/deep ad-hoc
  sealing. `rtk proxy bin/smoke` passed authenticated launch/pages, origin/replay
  refusal, heartbeat, graceful Quit and listener cleanup. Retained smoke data:
  `/private/tmp/ccoding-smoke.9wslCV`. Helper SHA-256:
  `b323abdbb538175920ddb774b9376c55b19853c399eb17945b618df829930bf0`.
- Source/diff review checked UUID scope, bounded queries/output, no native/provider
  calls, existing controller session/CSP/no-store protections and download links
  outside draft submission. No additional native/JS change or full browser/axe/
  Rust-suite rerun for this small host/download slice; preceding inspector browser
  evidence remains historical. Fixture HTTP tests are not real-provider acceptance.

No migration or runtime permission change. Additional log artifacts, full recovery,
parallel tasks, custom workflows/providers, timed setup and signed release remain
open. Local main integration only; no push/publication.
