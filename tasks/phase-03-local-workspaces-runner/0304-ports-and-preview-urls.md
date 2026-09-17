# 0304 — Port Allocation and Preview URLs

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

- [ ] Ports released on hibernate/stop, reallocated on resume.
- [ ] No two active runs share a port.
- [ ] Health status visible.

## Acceptance criteria

- [ ] Concurrent allocations never collide.
- [ ] Preview URL reachable in the e2e sample project.

## Verification and evidence

Run allocator concurrency tests and the dev-server lifecycle test.
