# Autonomous delivery

The owner-directed priority from 2026-11-02 is to complete work from the initial
specification with as little intervention and delay as possible. A question or
failed attempt should first produce a diagnosis by another model and a fresh
implementation attempt. The desired outcome is a verified integrated change.

## Model policy

New workflow admissions retain autonomy version 1 (five implementation cycles,
forty-eight stages) and pin routing version 2. Earlier saved deliveries, queued
requests, intakes and Autopilot batches keep routing version 1. Explicit review or
candidate retries preserve their parent's routing and catalog; a fresh Start can
use the current routing policy. Replay never expands an old authorization.

Before the first agent stage, BOSS runs the fixed metadata command
`codex --config 'model_provider="openai"' debug models` outside the project, with
a 12-second execution bound, bounded cleanup and a 1 MiB output limit. It validates
visible supported models and reasoning levels, then persists a reduced immutable
catalog. The selected provider matches managed exec's default OpenAI provider;
managed configuration and cached metadata can still differ. Catalog presence is
metadata, not proof of account entitlement or a successful inference.

| Work | Routing version 2 |
| --- | --- |
| Planning and Codex review | Saved primary; prefer Sol and high reasoning when supported |
| First implementation, explicitly small plan | Available Luna, medium when supported; otherwise primary |
| First implementation, ordinary plan | Primary coding model |
| Diagnosis / second opinion | Distinct strong model; prefer Astra or Terra and xhigh when supported |
| Subsequent implementations | Alternate the saved resolver and primary strong model |

Supported identities are `gpt-6.1-sol`, `gpt-6-astra`, `gpt-6-luna`,
`gpt-5.6-sol`, `gpt-5.6-terra` and `gpt-5.6-luna`. Requested 6-series roles are
preferred where advertised; an installed CLI advertising only the supported
5.6-series uses those exact IDs. Hidden models, unknown aliases and CLI defaults
are not substitutes. At least two distinct supported strong models are required.
Every call's exact model and effort are saved before execution.

The planner may classify a task as small only when its change is narrow and
straightforward. Model choice does not change filesystem permissions, the selected
account, check configuration or original specification. An explicitly selected
Claude reviewer stays Claude. Every call uses a fresh session; diagnosis is guidance,
not approval. A replacement executor must reproduce the failure, make a focused
experiment, implement its result and run the saved checks.

Routing version 2 excludes a model only after a typed `model_unavailable` error,
natural process exit, both stream EOFs and known group cleanup. A generic nonzero
exit does not establish model unavailability. Auth, quota/rate, request-schema and
transport/protocol failures receive fixed sanitized diagnoses and stop another
model call. An unfavorable review or failed project check does not exclude a model.
Raw CLI messages and metadata are never persisted.

Historical autonomy1/routing1 retains its fixed Sol 6 / Astra 6 / Luna 6 profiles
and original nonzero-exit exclusion rule. Earlier autonomy0/routing1 keeps its
original CLI defaults and budget. Existing evidence is not rewritten.

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

A confirmed implementation-process failure retains its workspace, including
partial edits. Diagnosis uses a new read-only workspace at that attempt's saved
base commit; the replacement implementation uses another fresh workspace at the
same base. Partial failed output never becomes an accepted candidate implicitly. Routing version 2
also recognizes a typed semantic error with natural exit zero; exit zero alone is
not successful delivery.

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
review. New documentation intakes separately pin planning version 1: up to three
read-only attempts under one 20-minute deadline, with persisted model/source pins,
typed validation receipts and a distinct strong model after a recoverable failure.
The original documents and fixed failure diagnosis guide the replacement plan.
The latest valid plan hash binds task creation; historical planning version 0 and
failed requests are unchanged. Stop, unknown cleanup, drift and shared provider
failures halt this bounded loop. See [Autopilot](AUTOPILOT.md).

Integration still stops on conflicts, candidate/target drift
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
dated worklogs. Finite native CLI acceptance covers planning questions,
rejected changes, unavailable model exits, partial implementations, Stop and Repo
loss. Before routing version 2, the complete macOS application regression passed
660 tests with one Linux-only skip (seed 1208). Current catalog-routing and recovery
results are recorded in the November3 worklog. Real account availability, cost
and delivery speed remain unverified.
