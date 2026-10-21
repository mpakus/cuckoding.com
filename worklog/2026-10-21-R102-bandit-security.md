# R102 — Bandit advisories and current audit gate

Claimed 2026-10-21 from local main `e8fbb42` after R080i merge/branch deletion.
The user's `Untitled.md.age` remains untouched. Ponytail full 5.3.2 (MIT), local
security/quality and the installed dependency-review guidance apply. RTK proxy
preserves exact audit/build/HTTP evidence. No app instance is running.

The R080i build's fresh Hex metadata flagged Bandit 1.12.5 while the existing
`deps.audit` returned clean. Official sources inspected before the upgrade:

- [HTTP/2 deadline advisory](https://github.com/mtrudel/bandit/security/advisories/GHSA-69m6-wcv4-rwcf): versions below 1.13.0 affected.
- [HTTP/1 authority advisory](https://github.com/mtrudel/bandit/security/advisories/GHSA-v53v-9hvg-37jf): versions below 1.13.0 affected.
- [Changelog](https://github.com/mtrudel/bandit/blob/main/CHANGELOG.md): 1.13.0 fixes both and requires Thousand Island 1.6; 1.13.1 reverts a stale-connection check that broke valid Phoenix error rendering.

Choose Bandit 1.13.1 or compatible patched version, inspect its actual package
source/changelog and transitive lock delta. Keep loopback/origin/session controls;
no permissions, accounts or provider inference are changed. Hex's installed
`mix help hex.audit` requires its check before application-loading tasks; place
it first in quality, without shipping Hex in `extra_applications`.

Resolved Bandit 1.13.1 and required Thousand Island 1.6.0 with `mix deps.update
bandit`. Verified the lock diff contains exactly those two packages. Actual
downloaded changelogs match the official release notes; Thousand Island caches
peername at accept, improves ownership-transfer/accept failures, handshake/read
timing and port-zero binding. Existing hpax 1.1.0 already meets the new floor.
No package source or checksum was hand-edited; all other locks are unchanged.

Verification:
- Before upgrade `rtk proxy mix hex.audit` exited 1 for both advisories while
  the old local audit was clean. After upgrade it exits 0 with no advisory or
  retired package. Added it first to `quality`; no ignore list or Hex runtime app.
- Added two real raw-loopback Bandit/Endpoint regressions: origin/local/foreign
  absolute targets, malformed userinfo/fragment/NUL authority, JSON parse-error
  rendering and subsequent listener service. Ephemeral listener is supervised and
  stopped by ExUnit; bounded sockets close in `after`. The test endpoint's static
  logical port is documented rather than presented as the packaged dynamic port.
- Controlled downgrade experiment: saved both new project/lock files, restored
  the original 1.12.5/1.5.0 cohort through Mix, and ran the new transport tests.
  One failed (403 from application instead of server 400), exit 2. Restored both
  files and patched packages in `finally`; no app/user workspace was running.
- Final `rtk proxy mix quality`: 433 tests pass; format, warnings-as-errors
  compile, strict Credo, Sobelow and both audit sources pass. Existing Sobelow
  generated-lockfile keyword warnings remain nonfatal.
- Inspected both HTTP/2 connection and stream send paths in the installed
  package: both use progress-based deadline extension. Did not run a trickle/DoS
  workload or import private dependency implementation into product code/tests.

No provider inference, profile access, migration, browser redesign, native code
change or permission expansion. Native attack/load, real accounts, physical
sleep, clean-machine and signing/notarization acceptance remain separate gates.

Final `bin/dev.build` passed, including production compilation and strict/deep
ad-hoc bundle verification; no fresh dependency advisory warning. Inspected the
actual packaged `.app` records: Bandit 1.13.1, Thousand Island 1.6.0, no Hex runtime.
`bin/smoke` passed launch/bootstrap/authenticated pages/origin/replay/heartbeat/
normal quit/listener cleanup; retained `/private/tmp/ccoding-smoke.75Uupn`.
Helper SHA-256: `4c49bc15373253bc5e264edc63914076d22b7ed4237999f6f9a93df85683ede2`.
Final review made the test socket read a complete status line (`packet: :line`)
rather than assuming TCP packet boundaries; both focused tests passed afterward.
Product source/locks stayed unchanged after the full quality/build. Local links
and diff whitespace checks passed. No native test-suite rerun was needed for this
dependency/transport-only slice. Local merge only; no push/publication.
