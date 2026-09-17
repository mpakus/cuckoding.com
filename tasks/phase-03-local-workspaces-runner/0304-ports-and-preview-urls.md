# 0304 — Port Allocation and Preview URLs

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0304-port-preview.md
```

## Objective

Implement per-project port ranges, allocation and release, `PORT`/`CUCKODING_PORT` injection, dev-server start via declared command, health probing, and preview links in the UI..

## Dependencies

- 0302.

## Scope

Implement per-project port ranges, allocation and release, `PORT`/`CUCKODING_PORT` injection, dev-server start via declared command, health probing, and preview links in the UI.

## Deliverables

- Port allocator with constraints.
- Dev-server management and health probe.
- Preview link and worktree open actions.

## Checklist

- [x] Ports released on hibernate/stop, reallocated on resume.
- [x] No two active runs share a port.
- [x] Health status visible.

## Acceptance criteria

- [x] Concurrent allocations never collide.
- [x] Preview URL reachable in the e2e sample project.

## Verification and evidence

Run allocator concurrency tests and the dev-server lifecycle test.
