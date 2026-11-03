# Autonomous delivery

The owner-directed priority from 2026-11-02 is to complete work from the initial
specification with as little intervention and delay as possible. A question or
failed attempt should first produce a diagnosis by another model and a fresh
implementation attempt. The desired outcome is a verified integrated change.

## Model policy

New workflow admissions pin policy version 1 before model effects. Existing
deliveries, queued requests, intakes and Autopilot batches keep version 0. Replaying
an old request cannot silently buy a new policy or expand its attempt budget.

| Work | Version 1 route |
| --- | --- |
| Planning and Codex review | GPT-6.1 Sol, high reasoning |
| First implementation, small scoped plan | GPT-6 Luna, medium reasoning |
| First implementation, ordinary plan | GPT-6.1 Sol, high reasoning |
| Diagnosis / second opinion | GPT-6 Astra, xhigh; then Sol, xhigh if unresolved |
| Subsequent implementations | Astra xhigh, Sol xhigh, Astra xhigh, Sol xhigh |

The planner may classify a task as small only when its change is narrow and
straightforward. Missing classification uses the ordinary route. Model choice
never changes filesystem permissions, the selected account, check configuration
or the original specification. An explicitly selected Claude reviewer stays Claude.
Every model call uses a fresh session; a diagnosis is guidance, not approval.

A confirmed nonzero model-process exit excludes that model from later stages of
the same delivery only after both streams end and process-group cleanup is known.
Routing tries the preferred model, then the remaining Sol/Astra option with xhigh
reasoning. Luna is eligible only for the initial explicitly small implementation.
An unfavorable review or failed project check is not evidence of model unavailability.
If no eligible model remains, the workflow reports exhausted model routes instead
of silently using a CLI default. Every selected profile is saved before execution.

Model IDs are `gpt-6-astra`, `gpt-6.1-sol` and `gpt-6-luna`. The installed Codex
CLI accepts `--model` and the `model_reasoning_effort` configuration override.
Official model documentation describes the requested reasoning levels:
[Astra](https://developers.openai.com/api/docs/models/gpt-6-astra),
[Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol),
[Luna](https://developers.openai.com/api/docs/models/gpt-6-luna).
These contracts do not establish access or quota on a particular local account.

## Resolve before asking

A resolver receives the original specification, saved plan, exact candidate,
structured findings and complete available check output. It inspects read-only,
identifies the cause, chooses ordinary engineering defaults and returns bounded
steps and assumptions. Its persisted report explains the decision; raw transcripts
and check output remain transient.

An initial planner question is followed by resolution and a fresh plan. Once
acceptance criteria exist, a replan must preserve their exact strings. A failed
check or rejected review retains its candidate and complete transient feedback;
the next implementation starts in a fresh worktree and is checked and reviewed
again. A repeated failure does not immediately terminate a version 1 delivery:
the implementation model changes before the remaining attempt budget is used.

A confirmed nonzero implementation-process exit retains its workspace, including
partial edits. Diagnosis uses a new read-only workspace at that attempt's saved
base commit; the replacement implementation uses another fresh workspace at the
same base. Partial failed output never becomes an accepted candidate implicitly.

Version 1 allows at most five implementation cycles and forty-eight persisted stages.
The second opinion must use a different eligible strong model. Its attempts are
bounded as well. The budget prevents an unresolved task
from consuming models indefinitely; independent eligible tasks can still proceed.
Legacy version 0 keeps its original three-cycle/twenty-stage behavior.

The resolver cannot change acceptance criteria, fabricate credentials, invent
infrastructure evidence or mark a task Done. Owner Stop, uncertain process cleanup,
unresolved storage effects and candidate tampering retain their existing handling.
After both opinions, a genuinely unavailable external action is reported precisely.
The workflow remains unfinished when intervention is required.

This recovery loop covers managed delivery planning, implementation, checks and
review. Documentation intake pins the model policy but does not yet run this
resolver loop itself. Integration still stops on conflicts, candidate/target drift
or failed publication checks; it does not automatically rewrite the approved
candidate. These are explicit remaining autonomy work, alongside provider testing.

## Acceptance

The acceptance target is an initial question or rejected implementation proceeding
through model escalation to passing checks, independent review, publication and
postchecks without an intervening owner action. Verification must use finite local
CLIs first and keep real-provider acceptance separate.

Track accepted results without intervention, total owner time including setup,
elapsed delivery time, model cost per accepted result and defects found afterwards.
Do not improve these numbers by weakening tests or renaming unfinished work Done.

Implementation and verification results are recorded in `tasks/todo.md` and the
2026-11-02 worklog. Finite native CLI acceptance covers planning questions,
rejected changes, unavailable model exits, partial implementations, Stop and Repo
loss. The complete macOS application regression passed 660 tests with one
Linux-only skip (seed 1208). Real account availability, cost and delivery speed
remain unverified.
