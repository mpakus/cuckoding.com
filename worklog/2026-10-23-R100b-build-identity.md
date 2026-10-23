# R100b — Identify the actual local build

Claimed on `feature/R100b-build-identity`, base `165e7a2`. The preceding goal turn
made verified state changes: retained candidate recovery and responsive/task-editor
fixes merged into local main. Only unrelated untracked `Untitled.md.age` exists;
it remains unread, unmodified and unstaged.

RTK, Ponytail full 5.3.2 MIT, architecture, menubar-shell, security and quality
guidance apply. No new dependency, provider use or publication. Exact current
source is authoritative; historical test/build counts are not current evidence.

Acceptance: bounded public metadata and an application-input digest, identical
native/release binding before migration/dispatch, honest source-preview state,
authenticated Settings disclosure and retained sealed-artifact receipt. No
credential/profile/path data or new execution grant in the metadata. The digest
covers enumerated application inputs, not dependency provenance or a signed
release proof. Record D047 before changing this startup boundary.

Parallel provider research found an authentication contract that needs a human
choice. The official Claude Agent SDK overview states that third-party products
need prior approval to offer claude.ai sign-in. Asked whether to use API-key
authentication or await that approval; no Claude account/credential was accessed,
provider installed or inference attempted. Source checked 2026-10-23:
https://code.claude.com/docs/en/agent-sdk/overview . This does not change provider
support or silently replace the requested account. Build work proceeds independently.

## Implemented

`bin/build-info` generates a format-one, thirteen-field public manifest with a
fresh UUID/date, source revision/dirty boolean, explicit application-input digest,
target, schema generation and tool versions. It hashes bytes, relative paths and
execute bits, including newly added source files; unrelated root files and private/
generated output are excluded. Links/special inputs, oversized trees/files and
changes during reading/build refuse evidence. Output creation refuses linked/
special/hardlinked files, and build receipts use exclusive creation.

Both the native shell and Phoenix BEAM embed identical manifest bytes. The shell
checks its regular bounded release copy before data preparation, then passes
only public UUID/digest. Production config checks its own compiled copy before
Storage, SQLite migrations or dispatch. Bootstrap confirms the running build ID.
The first implementation used a runtime file reader; Sobelow flagged its dynamic
path. Removed that reader entirely in favor of the stronger compiled binding,
without a waiver. Source development has no packaged identity, even when generated
files exist. Settings adds a public build row/disclosure, not another setup step.

The builder verifies its input snapshot after compilation/sealing, compares the
native report and release manifest, verifies the strict/deep seal and exclusively
retains actual helper/resource-manifest hashes under `.ccoding/build-receipts/`.
The receipt explicitly records release acceptance false. No DB migration,
provider/workflow grant, profile access or historical run rewrite was added.

## Verification

Pinned tools: Elixir 1.20.3-OTP28, OTP 28.5, Rust 1.97.1. Commands used
`rtk proxy env PATH=/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.

- Python and Elixir tests initially failed because the generator/BuildInfo module
  did not exist. The initial `python3 -m unittest test/...` invocation collided
  with Python's standard `test` module; the direct script invocation is canonical.
- `rtk proxy python3 test/build_info_test.py`: **4 passed**. Covers new file/byte/
  mode changes, unreadable unrelated canary, links/FIFO, generated output links/
  hardlinks, exclusive receipt preservation and post-build source/manifest drift.
- `rtk proxy env PATH=<above> mix quality`: **557 passed**, format,
  warnings-as-errors compile, strict Credo, Sobelow and dependency audits passed.
  Initial Credo findings were resolved with a closed typed pattern and fixture
  moduledoc; the runtime File.open API was removed after Sobelow's finding.
  Existing migration/dependency warnings remain; none suppressed.
- `rtk proxy env PATH=<above> cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`:
  checked before integration. `cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`:
  passed. `cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  **98 passed, 5 existing environment-dependent ignored**, 226.60 seconds.
- The native regression covers exact/missing/changed/oversized/linked metadata,
  invalid calendar dates and unknown/secret-canary fields. Host tests cover the
  closed public shape, exact compiled UUID/digest, bounded input and no source
  fallback. Settings tests cover public/invalid/source states; bootstrap/power
  regressions pass with the additional public build ID.
- Removed the final digest equality check temporarily: the changed-manifest
  exception assertion failed (1/2 passed). Restored exact source in `finally`,
  then the six focused BuildInfo/Settings/shell tests passed. No source preview
  was live; the packaged QA used its immutable bundled BEAM. The input digest
  was reverified against the tested package after restoration.
- `rtk proxy python3 test/reset_agents_test.py`: passed against disposable fixtures
  only. No real workspace reset ran.
- `rtk proxy env PATH=<above> bin/dev.build`: passed; shared compiled manifest,
  final seal and exclusive artifact receipt verified. `rtk proxy bin/smoke`:
  passed launch/bootstrap, cookie, handoff replay/origin refusal, heartbeat,
  graceful quit/listener cleanup. Fresh data: `/private/tmp/ccoding-smoke.MGCpQr`.
- Actual packaged helper refused four isolated release fixtures (missing, foreign,
  oversized and linked metadata) before data directory creation or a fake backend
  launch. Actual production BEAM refused wrong ID/digest and missing expectations
  before database creation or bootstrap-file consumption. Fixture artifacts remain
  private under `.ccoding/r100b-*`; no provider ran.
- Actual helper architecture verified `arm64` with `/usr/bin/lipo -archs`.
- Source integration smoke used separate `.ccoding/ui-dev` data and the ordinary
  launcher protocol, checking Settings' Source UI label while generated metadata
  existed. It passed strict CSP/reload/session/origin checks and shut down.
- A profile-free copy of schema-seventeen QA data ran the actual bundled release
  with `/usr/bin:/bin:/usr/sbin:/sbin` PATH and its own private runtime HOME.
  Headless Chrome used a fresh context, not the personal profile. Packaged Settings
  showed the exact build UUID/digest at 320/768/1024/1440 CSS pixels, no page overflow
  or JavaScript page errors. Keyboard disclosure and its open state survived ticks.
  Desktop/narrow screenshots were inspected; proofs remain `.ccoding/r100b-*`.

## Artifact and cleanup

Build `7f26834f-56d1-4a66-b5cc-ce8742353c8e` observed source `165e7a2` with local
changes (this task's input bytes are bound separately). Input SHA-256:
`43b4d4f781a5ef794baeb6d17a1158c09d203acd2030e2d91961cdf4d383fcdd`.
Helper SHA-256:
`cdf9b2748d1feaeb76dc0d423d9b4d48d52f13d483a1677a5de911be0cbe3ce3`.
Resource-manifest SHA-256:
`d65d91fa8140485cf4a9a1162df0361b6e1dedc1fe8865319f45ffc7361a60b5`.
The immutable private receipt has the same UUID under `.ccoding/build-receipts/`.
Ad-hoc sealing is not Developer ID provenance or notarization.

The first packaged-browser initialization did not reach the authenticated page
after setup delays; a normally restarted launcher supplied a fresh handoff and
the complete browser pass succeeded. On final shutdown, the backend/listener
closed but the copied Python QA launcher stayed alive with its data lock. Ctrl-C
and normal SIGTERM did not finish it. Verified PID 91034/start 2026-10-23 15:43:05,
executable and cwd against the exact private lock, no children, exited backend
91036 and no database file owner. Backed up its fixture database, then terminated
only that stuck launcher. It is not evidence of provider-process cleanup.

After terminal completion, its lock was available; all fourteen copied domain
table hashes matched source QA data, schema remained seventeen and integrity/FKs
passed. The original saved workspace/profiles were untouched. The observed
signal/Event handler race in the existing source launcher needs a separate focused
reproduction/fix (R011b); it is not silently marked solved here.

Implementation `8b32fc3` fast-forwarded into local `main`; feature branch deleted.
Documentation references and whitespace checks passed. Only unrelated
`Untitled.md.age` remains untracked, unread and unstaged. No paid inference, provider installation, publication,
notarization, physical sleep, unfamiliar-user timing or clean-machine/update
acceptance is claimed. The full beta goal remains active.
