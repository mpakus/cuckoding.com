# R040o — Versioned Tabula workflow foundation

Following local main `f2d21af`. Ponytail full 5.3.2 (MIT), architecture,
workflow/kanban, LiveView, security-review and quality-gates apply. All shell
commands use RTK; proxy retains exact source/protocol/test evidence. No new
dependency or provider/native grant. Keep `Untitled.md.age` and the old saved
user root untouched. Previous goal turn was progress: R060m/n were implemented,
verified and merged. The full beta objective remains active.

Read the immutable Tabula schema, ProjectChecks revision/command pattern, current
board/Start projections, session-guarded components and prior-schema tests.
D043 records the additive revision/label boundary before code. This foundation
must lead to actual custom stages, not replace that requirement with decorative
columns or claim the beta complete.

## Result and review

Added migration sixteen and `Workflows` as the single owner of current workflow
projection/history and audited label saves. Original Tabula definitions remain
unchanged virtual revision zero. SQLite enforces consecutive immutable revisions;
stable keys replay their original receipt. Immediate transactions enforce exact
Arena/Tabula/revision, active-planning/battle and closed bounded-name gates. New
Starts freeze their definition/revision. Roles, key order, provider tools and
review authority are unchanged. No dependency, native operation or second frontend.

Advanced → Board columns uses the shared modal, existing form styles and a
session-guarded component. Dirty text survives ticks/revision drift; recovered
forms cannot save without explicit reload. Board/draft/planning/specification
labels agree, while Inspect shows a battle's frozen names. Review followed tests,
callers, immutable schema/transactions, scope mutation, session handling and
bounded reads. No unresolved actionable issue was found after the browser fixes.

## Verification

- Red domain tests failed before the context existed. Focused domain/UI/migration
  checks passed; broader label/planning/specification checks passed. The final
  `rtk proxy env PATH=<pinned> mix quality` passed **524 tests**, compilation,
  formatting, Credo, Sobelow and both dependency audits. Existing migration-module
  redefinition and quoted lock-keyword warnings remain; no advisory was suppressed.
- Mutation: removed the exact Arena predicate in the workflow lookup. The
  cross-scope regression failed; restored the original bytes before subsequent
  edits. This checks real scope enforcement rather than only matching markup.
- Real source browser on isolated `.ccoding/ui-dev`: saved Mission brief/Queued,
  checked board labels, dated history, tick/dirty preservation, explicit Keep
  editing, Escape and focus return. Restored Specs/ToDo by another audited save,
  retaining both revisions. Browser testing exposed nested `_unused_` markers
  absent from fixture forms; a red regression now covers them and unknown markers.
  It also exposed unstyled implicit-type inputs; reused existing `role-fields`
  styling with explicit text inputs. Screenshot: `.ccoding/r040o-board-columns.png`.
  The available IAB viewport was 680 px; 320 px resizing was unavailable.
- `rtk proxy bin/dev.build` passed on the final source, including complete
  ad-hoc signing and strict/deep verification. Final helper SHA-256:
  `cbc3f02a90e8520364edb10ef2d3a38a09f3d3f91493c4417c75793ee9671404`.
  `rtk proxy bin/smoke` passed browser bootstrap/cookie, origin/replay refusal,
  heartbeat, graceful quit and listener cleanup. Smoke root:
  `/private/tmp/ccoding-smoke.SplBRZ`. Rust source was unchanged; native unit tests
  were not rerun for this metadata/UI slice.
- A final event-insertion failure regression verifies that neither the command
  nor workflow revision survives a transaction rollback. The full quality gate
  was rerun after adding it; the built product source was unchanged.
- Prior-schema tests upgrade eleven/fourteen/fifteen fixtures with immutable
  prior facts, integrity/FKs and readable private backups. Packaged upgrade of
  a **profile-free copied development database** passed fifteen→sixteen; all
  thirteen retained table facts matched the backup and workflow history was
  initially empty. The retained fifteen-schema shell refused the upgraded copy;
  its generic smoke error hid the reason, so a normal old-release startup under
  the exclusive lock verified the exact newer-schema exception, no Ready and
  exit 73. This was a harness observation fix, not a product change. Backup hash
  stayed `b05c1c449446f58d6475f96eefc72dd383ec4eb352110f56167ce0cef728791e`.
  Private metadata/logs: `.ccoding/r040o-package-proof.json`,
  `r040o-upgrade-smoke.log`, `r040o-quality-final.log`, `r040o-build-final.log`,
  `r040o-smoke-final.log`. No original saved user root or provider profile was used.
- Source preview launcher was a private QA copy of `bin/dev.server` that sent its
  normal fresh one-time handoff to IAB instead of `/usr/bin/open`; auth/lifetime
  checks were unchanged. The first handoff expired because it was consumed late;
  a fresh launch fixed the harness timing. Verified idle DB, PID/start/comm/cwd,
  shell lock and listener before normal TERM of only the owned launcher. Backup
  `.ccoding/r040o-ui-after-verification.db` retained. Launcher/backend exited,
  port 54175 closed and lock became free. No provider was launched or signed out.

All commands used RTK. `proxy` preserved exact SQL/source/JSON, process identity,
test/build diagnostics and shell exit status. `git diff --check` passed. Docs,
AGENTS and README distinguish implemented renaming from the still-required
add/reorder/custom execution stages, toolchain checks, recovery, additional
providers and live/sleep/release acceptance. No push/publication or memory edits.
