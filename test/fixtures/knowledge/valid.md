---
id: "019b0000-0000-7000-8000-000000000701"
kind: fact
title: "Use durable workflow state"
scope: project
status: project
version: 1
confidence: 0.95
valid_from: "2026-09-17T00:00:00.000000Z"
invalid_at: null
supersedes: null
evidence:
  runs:
    - "019b0000-0000-7000-8000-000000000001"
  repository_shas:
    - "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
produced_by:
  runtime: codex
  model: fixture-model
  policy_version: 1
triggers:
  - "when changing workflow state"
review: null
---
# Durable workflow state

SQLite is authoritative; workers reconstruct from durable identifiers.
