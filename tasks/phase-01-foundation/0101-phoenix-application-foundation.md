# 0101 — Create Phoenix Application Foundation

```yaml
status: done
owner: codex
started_at: 2026-09-17
worklog: worklog/2026-09-17-0101-phoenix-application-foundation.md
```

## Objective

Create the Elixir application with Phoenix LiveView and Tailwind, dev/test/release configuration, a supervision root, domain context placeholders, structured logging, health and status endpoints, injected clocks, and test tooling.

## Dependencies

- Phase 0 decisions accepted.

## Scope

Create the Elixir application with Phoenix LiveView and Tailwind, dev/test/release configuration, a supervision root, domain context placeholders, structured logging, health and status endpoints, injected clocks, and test tooling. Do not implement product workflows yet.

## Deliverables

- Bootable Phoenix application.
- Documented module/context boundaries: `Projects`, `Workflows`, `Execution`, `Adapters`, `Plugins`, `Knowledge`, `Power`, `Telemetry`, `Shell`.
- Formatter, compiler, test, static analysis, and dependency-audit commands.
- Basic LiveView shell and health/diagnostics page.

## Checklist

- [x] Pin supported Elixir, Erlang/OTP, Phoenix, and dependency versions.
- [x] Add correlation IDs to logs and requests.
- [x] Provide a `Clock` behaviour with monotonic and wall sources and a test implementation.
- [x] Prevent secrets from being logged in configuration inspection.
- [x] Add CI commands that mirror local checks.
- [x] Document developer setup and clean bootstrap.

## Acceptance criteria

- [x] A clean checkout boots and tests with one documented command sequence.
- [x] Compilation has no warnings.
- [x] Release configuration has no development-only endpoints or secrets.
- [x] Health output distinguishes application and dependency status.

## Verification and evidence

Run formatting check, compilation with warnings as errors, unit tests, static analysis, dependency audit, and a production-release boot smoke test.

Evidence is recorded in `worklog/2026-09-17-0101-phoenix-application-foundation.md`. The single `rtk mix quality` gate passes, and a production release served `/health` and `/status` only on `127.0.0.1` before clean shutdown.
