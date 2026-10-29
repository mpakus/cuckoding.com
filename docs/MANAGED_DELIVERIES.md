# Managed task delivery

The task drawer's **Start workflow** runs a managed workflow on macOS:
plan → implement → snapshot → checks → fresh review → optional fixes. Enter one
trusted check command first. **Integrate approved result** is a separate explicit
action. Only successful publication and post-integration checks move the task to
**Done**. The older manual runs/checks/reviews remain advisory and cannot be
promoted into this workflow.

Project-level [Autopilot](AUTOPILOT.md) explicitly authorizes automatic integration
for the saved whole-Backlog batch. It reuses these same stages and gates, running
one task through Done before starting the next. Ordinary Start/Queue remains manual.

Codex plans, implements and fixes. Select **Codex** (default) or **Claude** as
the independent reviewer before Start. The selection is saved for the whole
workflow, including every fix cycle. Install/sign in to the selected CLI on BOSS's
PATH; there is no automatic provider fallback. See [Claude review](CLAUDE_REVIEW.md).

## Inputs and stages

Admission saves the task's immutable source revision, current task version,
normalized check argv/config hash, reviewer and command UUID in an immediate transaction.
The persisted global capacity allows 1–3 managed workflows, default two. Predicted
file overlaps wait before implementation; unknown predictions are visibly flagged.
See [workflow scheduling](WORKFLOW_QUEUE.md). Manual execution and integration
remain globally exclusive; unknown cleanup blocks every new execution.
Identical request retries return the original delivery, including after completion;
changed input with the same UUID conflicts. A saved Ready result survives restart.
[Explicit source adoption](TASK_REVISIONS.md) retires an unintegrated Ready
approval and resets the task to New; the old plan/review remains historical.
Active/unknown execution, a pending queued request or an unfinished integration
intent prevents adoption.
New starts also require [dependency readiness](TASK_DEPENDENCIES.md) from the task's
pinned source. Only Done satisfies prerequisites; replay precedes that check.
A fresh explicit start after an external task cancellation retires the stale
Ready approval atomically; its review is never reused for the new workflow.

**Queue workflow** saves the same explicit inputs while waiting for capacity or
Done prerequisites. The queue does not change task state until actual admission.
Unstarted requests pause after restart and need explicit Resume. See the
[workflow queue](WORKFLOW_QUEUE.md) for cancellation, source pins and recovery.

The read-only Architect receives original source and returns a bounded, strict
JSON plan: summary, implementation steps and unique acceptance criteria. Original
Markdown is never rewritten. The implementation receives source and saved plan in
a fresh worktree. A private-index snapshot produces an immutable candidate commit
without modifying the implementation workspace or the user's checkout.
Planning and implementation also receive the saved check configuration, so they
can prepare for the exact command before the first check.

The entered command runs without implicit shell expansion, with the same saved
timeout/output bounds on every candidate. Exit 0 is insufficient: exact HEAD,
ref, clean index/files and actual tree must still match the candidate. Only a
normal process exit with both EOFs, confirmed group cleanup and complete UTF-8
output can produce passing checks or feedback for a fix.

If checks create unignored files (for example `_build/` in a new Mix project),
even exit 0 fails candidate verification. **Saved stages** shows the exit code and
explains the `candidate_changed` outcome, including historical receipts. Inspect
the retained worktree's Git status and add appropriate generated-artifact ignore
rules before a fresh workflow. Never ignore source/tests to make verification pass.
Raw check output is not retained and cannot be reconstructed from its hash.

A fresh review receives original source, saved plan, complete
original-base→candidate diff, check configuration/receipt, complete bounded check
stdout/stderr and previous feedback. Its structured acceptance set must exactly
match the plan. Approval requires all criteria passed and no issues. Candidate
identity and tree are verified before and after review. This is model assessment
plus the configured checks; its coverage is limited by the actual command and
criteria, not a general proof that arbitrary code is correct.
Codex can inspect the candidate through its read-only sandbox. Claude assesses
only supplied evidence, without model filesystem or shell tools.

Check text is transient and sent to the selected reviewer and Codex fixer; it is not stored in SQLite or browser
history. Persisted receipts contain sanitized counts/hashes, typed plan/review
reports, Git identity, exit/EOF/cleanup and stage links. Do not put secrets in
commands, source or output. Complete prompt input is limited to 1 MiB; reports
to 32 KiB. Oversized/incomplete input fails instead of silently truncating.

## Automatic fixes and Stop

A complete failed check or `changes_requested` review starts a fresh implementation
worktree at the exact rejected candidate, preserving previous workspaces. Source,
plan, full feedback and check receipt/output accompany the fix. The next review
still compares against the original base, so earlier changes remain in scope.

There are at most **three implementation/check/review cycles**. Repeated normalized
failure on the same tree/config blocks earlier. Exhaustion becomes `blocked`;
`needs_spec_revision` becomes `needs_input`. Invalid reports, changed snapshots,
truncated/non-UTF8 output, launch/provider failures and Stop do not trigger retries.
Plan and each agent invocation have a 20-minute bound; checks retain their saved
command limits. No paid/provider smoke run is repeated automatically by development
verification.

Stop addresses the project-scoped live worker directly, bypassing Manager and Repo
mailboxes. Closing the drawer/browser does not own the run. Lost worker, Repo or
receipt interrupts/quarantines the delivery; restart never reuses saved PIDs,
respawns stages or retries publication. Unknown cleanup blocks further execution.
There is no force-unblock or automatic crash-resume interface yet.

## Explicit integration and Done

Ready waits for **Integrate approved result**. An unchanged target fast-forwards
to the **exact reviewed commit**. If the target advanced from the original base,
BOSS pins its current SHA and constructs a separate merge candidate with two
parents: that target and the originally approved candidate. It retains the
original approval, runs the saved checks on the merge, then requests a fresh
review from the saved Codex/Claude reviewer. The drawer shows both approvals and
their distinct commit identities.

When the target advanced, choosing Integrate invokes the saved reviewer again
and may consume provider quota or incur charges.

The fresh review receives the original source/plan, complete original-base and
current-target diffs, original approval and new complete check output/receipt.
Exact candidate/ref/parents/tree and target are verified around validation.
A clean Git merge alone is not approval. Conflicts, rewritten target history,
failed checks, review rejection or another target change stop integration. There
is no automatic merge repair, rebase or review retry; retained history remains
available for inspection and a fresh workflow. A request for specification
clarification becomes Needs input.

The target branch must be free of user worktrees before validation starts. Switch
your checkout to another branch before integrating; BOSS will not switch it for
you. Merge construction does not change the user index or files; executable Git
merge drivers are rejected before effects.

Publication intent saves the expected target SHA and approved candidate before
effects. An ordinary BOSS-owned worktree reserves the target branch. After
revalidating the task version, review lineage, candidate and checkout ownership,
Git compare-and-swap updates only the expected old target. BOSS populates its own
reserved checkout and reruns the saved checks against that published SHA.

After passing postchecks, BOSS detaches only its own publication checkout at the
same SHA, retaining all files and freeing the target for the next task. Final
identity verification plus persisted publication/postcheck receipts allow Done.
Only Done satisfies dependencies and allows an explicitly queued dependent to start.

Checked-out targets, drift, dirty/mismatched candidates or failed checks cannot
become Done. If failure or Stop occurs after publication, the target may already
contain the candidate: BOSS retains the checkout and reports attention, without
rolling back the branch. A lost publication receipt is an unknown outcome, not
proof that the target was untouched. Inspect retained work before starting a new
workflow. Integration requests replay with the same UUID; failed integrations do
not automatically retry or reuse an old approval for a new target.

Existing symbolic or symlink target refs are rejected. Git's OID CAS does not
atomically exclude a deliberately concurrent out-of-band symbolic-ref replacement
between verification and update; do not manipulate refs concurrently with BOSS.
Detached descendants remain outside the native process-group guarantee.

## Persistence and verification

Delivery identity/configuration/intents and completed stage receipts are immutable;
terminal delivery history cannot be changed or deleted. Rows begin before effects.
Ready/Done have database guards as well as context checks. The task change and its
versioned event are part of the same Repo-pinned transaction as delivery progress;
caller-provided verdicts/SHAs cannot directly command a terminal task state.

Tests use finite fake CLIs, real Git, native macOS transport and exclusively created
SQLite databases with real pools. They cover rejection/fixes, full feedback, budget,
Stop, restart/replay, source preservation, target reservation, exact publication,
postcheck failure, configured capacity, overlapping scopes and unknown receipt/Repo loss.
One bounded packaged real Codex workflow with Codex review passed through verified
Done (3calls/100.875s,5/5 criteria); this is a tiny smoke, not general task or Claude
acceptance. Linux execution, clean-machine acceptance and public signing remain
open. See [release evidence](RELEASE.md) and `.worklog/` for exact scope/results.
