---
id: "019b0000-0000-7000-8000-000000000701"
kind: fact
title: "Use durable workflow state after restart"
scope: project
status: project
version: 2
confidence: 0.98
valid_from: "2026-09-17T00:00:00.000000Z"
invalid_at: null
supersedes: null
evidence:
  runs:
    - "019b0000-0000-7000-8000-000000000001"
  repository_shas:
    - "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
produced_by:
  runtime: human
  model: none
  policy_version: 1
triggers:
  - "when changing workflow state"
review:
  approver: "project owner"
  date: "2026-09-17T01:00:00.000000Z"
---
# Durable workflow state after restart

SQLite is authoritative; workers reconstruct from durable identifiers after every restart.
