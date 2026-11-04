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

## Continue retained work after an implementation timeout

`Boss.Deliveries.Retry.start_timeout/4` admits an explicit new request from a
terminal managed implementation timeout. It pins `execution_recovery_version: 1`,
the source implementation and terminal task event, original specification and
acceptance criteria, original Git base, check configuration, reviewer and model
catalog. Historical and ordinary requests retain version 0. Replaying the same
command returns the saved request; it never reopens the failed delivery.

The first stage validates and adopts the exact retained plan. Its typed
`retained_plan` outcome is source provenance, with no invented model, process exit,
EOF or approval. A saved snapshot intent precedes capture of the retained files
through a private Git index. A fresh check worktree runs the original command.
Complete check evidence and the captured commit go to a distinct model for
resolution before a fresh implementation workspace is created at that commit.
The first replacement uses a different eligible strong model from the timed-out
executor. Timeout does not establish that a model is unavailable.

Within this policy, another confirmed implementation timeout can preserve progress
through the same snapshot/check/resolution path. Five implementation cycles and
48 stages remain the limit. Stop, unknown cleanup, missing stream closure and
unverified source identity do not qualify. A check timeout is not a passing check
or a complete failed-check report. Source files, locked dependencies, full original
acceptance and original-base review remain required; no generated path or adapter
is excluded to manufacture a pass.

A retained plan or partial snapshot does not authorize Ready or Done. Independent
review, exact-commit publication, postchecks and retained checkout verification
still apply. A direct timeout retry requires explicit integration when Ready;
it does not restart the old Autopilot batch or authorize subsequent tasks.

## Checkpoint recovery and dependency access

`Boss.Deliveries.Retry.start_checkpoint/4` creates a fresh, explicit recovery
request from an eligible terminal retained implementation/checkpoint. It saves
`checkpoint_recovery_version: 1`, the immutable source check when present, and
`implementation_network_version: 1`. Historical requests remain unchanged. The
same command UUID replays the saved child without another execution.

The source candidate is revalidated, captured into a fresh worktree, and checked
again before a distinct model diagnoses it. A check timeout is eligible only with
actual termination, both stream closures, known process-group cleanup and a fresh
unchanged-candidate verification. Its receipt stays a timeout with incomplete
output. Diagnosis receives no fabricated output or hash. This new policy also
permits diagnosis of such later check timeouts within its existing cycle/stage
budget. Changed candidates, Stop, unknown cleanup and output-limit failures remain
closed. A diagnostic timeout never satisfies review, publication or Done gates.

Only implementation receives the saved network policy: workspace-write remains in
force, public traffic uses a fixed package-host allowlist, and local binding is
enabled for local development services. The local option permits broader local
and private network access; it is not a PostgreSQL-port-specific exception. No host
settings are modified. Read-only planning, resolution and review retain their
existing network policy. The model receives the implementation policy as context,
but this capability is not evidence that dependency installation or tests passed.

Resolution reports retain the 32,768-byte total and decoded UTF-8 field limits.
The schema and prompt now state both budgets; invalid output is never truncated.
A rejected report records only a fixed validation code and byte count in its
summary, which the next resolver receives without raw private output.

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

Project commands run without the four launcher-owned defaults `MIX_ENV`, `PORT`,
`PHX_SERVER` and `BOSS_DATA_DIR`. Explicit per-child environment overrides still
win; PATH and the project's CLI/toolchain remain unchanged. This prevents a local
BOSS launch from making `mix test` select development mode or bind BOSS's port.
It does not select test mode for arbitrary commands or rewrite earlier receipts.
