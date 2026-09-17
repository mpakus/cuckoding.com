# 0101 — Create Phoenix Application Foundation

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

- [ ] Pin supported Elixir, Erlang/OTP, Phoenix, and dependency versions.
- [ ] Add correlation IDs to logs and requests.
- [ ] Provide a `Clock` behaviour with monotonic and wall sources and a test implementation.
- [ ] Prevent secrets from being logged in configuration inspection.
- [ ] Add CI commands that mirror local checks.
- [ ] Document developer setup and clean bootstrap.

## Acceptance criteria

- [ ] A clean checkout boots and tests with one documented command sequence.
- [ ] Compilation has no warnings.
- [ ] Release configuration has no development-only endpoints or secrets.
- [ ] Health output distinguishes application and dependency status.

## Verification and evidence

Run formatting check, compilation with warnings as errors, unit tests, static analysis, dependency audit, and a production-release boot smoke test.
