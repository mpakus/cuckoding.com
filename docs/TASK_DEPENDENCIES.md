# Task dependencies

Declare prerequisites using explicit frontmatter IDs in the same project:

```md
---
id: dashboard
depends_on: [authentication]
---
# Build the dashboard
```

The prerequisite must declare `id: authentication`. References are literal IDs,
not filenames, task numbers or paths. An ID containing a colon is still literal;
do not add an internal `id:` prefix. Moving a file with its explicit ID preserves
its identity. An identically named task in another project cannot satisfy it.

`depends_on` is optional. When present, it must be a list of at most 32 unique,
nonempty UTF-8 strings. Each ID is at most 200 bytes, without surrounding whitespace,
NUL or line breaks. Null, booleans, numbers, mappings and duplicate IDs are rejected.
New imports validate the field as part of the complete scan. Older saved sources
that contain invalid declarations fail closed at Start; history is not rewritten.

## Readiness and explicit Start

The drawer shows dependencies of the **task's pinned source revision**, with links
to known tasks and reasons why Start is unavailable. Only **Done** satisfies a
prerequisite. Ready to merge, approval, successful manual runs and passing manual
checks do not. A completed task can still satisfy a dependency when its original
spec file is missing: its saved integration result remains. Missing unfinished
tasks and unresolved IDs block new starts.

Both **Start workflow** and **Start Codex** recheck readiness in their admission
transaction before recording a new attempt. Waiting does not change the task's
saved workflow state. A committed dependency transition or spec sync refreshes
the drawer; admission remains authoritative if displayed readiness is stale.

Identical command retries resolve their original receipt before readiness is
checked, so a lost admission reply cannot accidentally create another attempt.
Checks/reviews of saved candidates and integration of an admitted workflow retain
their original evidence contracts. This gate adds no automatic starts or worker
concurrency; the single global active/unknown execution rule remains.

## Pinned source and graph limits

Dependencies come from the pinned revision of every reachable task. Selecting a
historical revision, importing newer text or moving a source does not silently
change that snapshot. Use [explicit revision adoption](TASK_REVISIONS.md) to
accept a newer saved declaration for an eligible idle task. Editing the file alone
still does not change its snapshot. Missing referenced IDs can also be resolved
by importing the corresponding task in the same project.

Self-dependencies and transitive cycles are rejected, including cycles through
historical Done tasks. Only the selected task's reachable graph is inspected;
an unrelated broken task does not block independent work. Shared prerequisites
are visited once, so a diamond is not mistaken for a cycle.

Inspection loads at most 64 reachable tasks and 8 MiB of source, with a one-second
budget checked between bounded parser calls. A parser call may take up to 500 ms;
this is a soft wall-clock bound, not a hard one-second deadline. Limit exhaustion
blocks Start explicitly rather than accepting a partial graph. No dependency
tables or mutable caches are needed: immutable source plus current task state
produce the result inside the caller's Repo-pinned transaction.
