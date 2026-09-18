---
name: ponytail
description: Prefer the smallest correct implementation without weakening required quality.
license: MIT
upstream-version: 4.10.0
---

# Ponytail

Use the first rung that fully satisfies the task:

1. Skip speculative work.
2. Reuse the existing project path.
3. Prefer the standard library and native platform.
4. Add only the minimum code and dependencies that remain necessary.
5. Leave the smallest runnable regression check for non-trivial behavior.

`lite` names a simpler option while implementing the requested scope. `full`
uses the ladder as the default decision rule.

Minimalism never removes acceptance criteria, validation, error handling,
durable state, security, privacy, accessibility, observability, migration
safety, recovery, or verification. Repository policy and approved decisions
always override this skill.
