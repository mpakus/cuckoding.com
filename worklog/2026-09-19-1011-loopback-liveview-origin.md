# Worklog — 1011 loopback LiveView origin

## Acceptance criteria

Allow the two supported loopback origins without weakening the loopback-only
listener, and keep Phoenix development reloads connected to Mix.

## Baseline

- Branch: `fix/1011-loopback-liveview-origin`
- Browser smoke logged a rejected `http://localhost:4000` socket origin while
  the endpoint canonical URL was `127.0.0.1`.
- Phoenix 1.8 also reported the missing `Phoenix.CodeReloader` Mix listener.
- Mandatory Ponytail, LiveView, security-review, and quality-gate guidance
  remain active.
- Preserved the unrelated untracked root `icon.png`.

## Implementation

- Added an explicit endpoint origin allowlist for `127.0.0.1` and `localhost`;
  the listener remains bound to `127.0.0.1`.
- Added Phoenix's required development code-reloader Mix listener.
- Documented and regression-tested the loopback-only origin boundary.

## Verification

- `rtk mix format --check-formatted` — passed.
- `rtk mix compile --warnings-as-errors` — passed.
- `rtk mix test test/cuckoding/config_test.exs test/cuckoding/board_task_intake_test.exs test/cuckoding_web/board_live_test.exs`
  — 11 tests, 0 failures.
- `rtk mix test` — 10 properties and 237 tests, 0 failures. The logged fixture
  crashes are the expected restart inputs in `Plugins.SupervisorTest`.
- `rtk mix credo --strict` — 193 files, no issues.
- `rtk mix sobelow --config` — scan complete with no findings.
- Browser smoke — both `http://localhost:4000` and
  `http://127.0.0.1:4000` reached a `[data-phx-main].phx-connected` root; the
  browser was left at `127.0.0.1`.
