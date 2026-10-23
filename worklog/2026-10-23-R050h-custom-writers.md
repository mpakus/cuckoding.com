# R050h — Custom writer stages

Claimed 2026-10-23 on `feature/R050h-custom-writers`; base `bb5ccc7`.
Unrelated `Untitled.md.age` remains untouched. RTK prefixes every shell command;
`rtk proxy` preserves exact source/test evidence. Ponytail full 5.3.2 (MIT).
Relevant workflow, architecture, security, local runner, LiveView and quality
skills apply. No new dependencies or runtime tools. A forward-only compatibility migration is required.

Acceptance: explicit bounded custom read/write stages around Implementor, immutable
workflow policy and writer checkpoints, cumulative capture, independent final review,
fresh-worktree writer retry, historical compatibility and guarded Advanced UI.

Design: reuse existing native capture/verify operations. Original worktree/index
stay based on the reviewed head. Each successful writer is captured using the
cumulative final path hashes from exact immutable successful attempts for that
preparation; later stages verify the latest retained candidate. No partial
integration or runtime shell/file/network permissions.

Implemented version-four workflows, explicit Access/Run selectors and canonical
per-position ordering in the existing guarded Advanced dialog. Historical v3
read stages/API receipts remain unchanged; blank/missing policies cannot write.
Start/Inspect disclose configured access. Native capture is required after each
writer; later turns verify the exact retained candidate receipt before inference.
A final source review strengthened the verification-response binding and added
foreign-receipt refusal before provider usage. Writer retry starts a fresh
worktree/coordinator/Speculator; Pause resumes at capture without replay.

Focused tests were first red for missing configuration and then missing writer
evidence. The final full `rtk proxy env PATH=<pinned toolchain> mix quality` passed:
541 tests, warnings-as-errors compilation, strict Credo, Sobelow and both Hex
checks/audits. Earlier Credo failures were fixed by keeping effect aggregation
and binding checks in focused helpers; no thresholds/exclusions changed. The
suite still emits preexisting migration redefinition and dependency quoted-keyword
warnings. Native fmt/clippy passed; full locked cargo tests: 96 passed, five
ignored. Those five require selected executables/environment or explicit real
account usage; none is claimed as provider acceptance.

The native regression proves successive captures on the original base, last
writer bytes, retained earlier paths, old-checkpoint drift refusal and original
source/index preservation. Executor tests cover cumulative edits followed by a
reader, mandatory independent task/final reviews, pause/capture, fresh writer
retry, file-limit/foreign evidence/native receipt refusal, and all four offered
mixed stages at maximum escaped summary sizes through correction rounds. Inverting
the new write-access condition made the focused regression fail; source was
restored in a finally block (`.ccoding/r050h-mutation.log`).

Real source browser at 680 px on private `.ccoding/ui-dev`: saved and reloaded a
custom Read/edit stage after Implementor; verified matching column order, scoped
Start repair, disabled Up/Down boundaries, explicit Start Inspect access and
Escape/focus restoration. `.ccoding/r050h-custom-writer.jpg` retains the screen.
No provider was launched; the QA role has no account/model. Hot compilation
briefly caused a component-unavailable tick; after reload the final stable checks
passed. This is not crash recovery acceptance. Idle commands/battles, DB integrity/
FKs and launcher PID/start/comm/cwd/lock/listener were verified; private before/
after backups retained. Normal TERM to the owned launcher requested graceful
shell quit. Both launcher/backend exited, listener closed and lock became free.

Final review found that schema-sixteen bundles could interpret version-four
workflows without their writer continuation policy. Added the seventeenth forward-only
migration as a compatibility barrier plus the exact task/preparation writer index.
A backed-up sixteen-schema fixture upgrades without changing facts and retains a
readable backup; EXPLAIN confirms the index. Packaging was repeated after this
change. `rtk proxy bin/dev.build` and strict/deep ad-hoc signature verification
passed. `rtk proxy bin/smoke` passed on fresh private data
(`/private/tmp/ccoding-smoke.1xdJn2`). The profile-free copied schema-sixteen QA
database upgraded to seventeen and passed the same bundle smoke, preserving all
14 domain table projections with integrity/FKs and its readable pre-upgrade backup.
The retained prior-schema bundle passed on its schema-sixteen control and failed
on the upgraded copy; its known migration list lacks only the new version.
The helper intentionally sanitizes that failure; no raw child diagnostics were
exposed. `.ccoding/r050h-package-proof.json` retains the exact copied-data facts.
Final native helper SHA256:
`d7f4328b9973b4178166d61709ef5dfc6b195bdcbe42c44001cd4fd52d423f21`.
CodeResources SHA256:
`f37c826fc8c8a9bddf760acb261d823b450ffe4656e227354c29420eaf78bc29`.

Final source/security review and documentation-link/whitespace checks passed.
Local integration pending. Real-provider, general subprocess/toolchain, broader
recovery/sleep, remaining provider and signed/clean-machine release gates remain
open. No push/publication or memory edit.
