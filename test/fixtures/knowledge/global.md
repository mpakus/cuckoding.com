---
id: "019b0000-0000-7000-8000-000000000702"
kind: pattern
title: "Persist before broadcasting"
scope: global
status: global
version: 1
confidence: 0.9
valid_from: "2026-09-17T00:00:00.000000Z"
invalid_at: null
supersedes: null
evidence:
  runs:
    - "019b0000-0000-7000-8000-000000000002"
  repository_shas:
    - "cccccccccccccccccccccccccccccccccccccccc"
produced_by:
  runtime: codex
  model: fixture-model
  policy_version: 1
triggers:
  - "when adding live updates"
review:
  approver: "project owner"
  date: "2026-09-17T02:00:00.000000Z"
---
# Persist before broadcasting

Commit the event before sending a best-effort live notification.
