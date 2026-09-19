# 1009 — Start PubSub before recovery

## Goal

Keep the Phoenix development server bootable when startup reconciliation emits an activity event.

## Acceptance criteria

- [x] `Cuckoding.PubSub` starts before runtime children that publish activity events.
- [x] Startup reconciliation keeps its existing persistence and recovery behavior.
- [x] The development web server starts with the existing active-run database and responds on loopback.
- [x] Focused and full verification results are recorded in the worklog.

## Verification

- `rtk mix format --check-formatted`
- `rtk mix compile --warnings-as-errors`
- `rtk mix test test/cuckoding/reconciler_test.exs`
- `rtk mix phx.server`
- `rtk git diff --check`
