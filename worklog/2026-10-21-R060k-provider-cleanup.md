# R060k — Explicit native cleanup

Claimed after R080h merged locally as 42e1741; task branch deleted. Ponytail full
5.3.2 (MIT), agent-adapter/local-runner/security/quality, Rust lifecycle/FFI and
installed incremental/review guidance apply. Use RTK proxy for exact native and
process output. Untitled.md.age remains excluded; no live provider use is granted.

Recovery inspection found `probe::Group::drop` sends TERM/KILL and discards `wait`
errors. Provider helpers therefore cannot return an explicit verified closure
fact before returning a result. Strengthen that prerequisite first: preserve
unreaped leader ownership until final signalling, bound waits, verify group
disappearance and surface uncertainty. Missing receipts, escaped descendants,
hard-killed Cursor session stores and full restart reconciliation remain separate.

## Result

The shared native guard now explicitly finishes every spawned Codex/Cursor,
version, Git and isolation child. Keep the leader unreaped through final TERM/KILL;
wait at most one second for exit and one for group disappearance, cache the result
and never signal after reaping/lost ownership. Post-spawn early errors use the same
path. Cursor catalog failures cannot mask uncertain closure; task turns retain
their private runtime store if the group could not be verified closed. Public
tool/edit evidence remains available without accepting the successful report.

The new host regression reproduced a second defect: public normalization dropped
`cleanup_verified: false`, then cancellation promoted zero-exit `cancelled` to
verified. Shared bounded native-receipt decoding now refuses false/malformed flags
before every provider projection; NativeHelper cancellation preserves that refusal.
Existing missing-field receipts remain compatible, not new recovery authority.
The existing TaskTurn malformed-flag test now also requires the retained false
flag, safe tool evidence and absent success report; it does not weaken refusal.

## Verification

- Red: two native Group tests could not compile before the explicit guard API.
  Added descendant/peer, cached repeat and lost/reaped-leader checks.
- Red: host tests observed `supported` for an unverified version and `cancelled`
  with verified closure after the normalizer had discarded false. Both now refuse.
- `rtk proxy cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  **81 passed, 5 ignored**, 218.15 seconds. Ignored provider/sandbox acceptance is
  not passing evidence. Focused probe tests: seven passed.
- Cargo fmt and Clippy `--locked --all-targets -- -D warnings`: passed. One
  compile-time mutable-owner error was corrected before these checks.
- `rtk proxy env PATH=<pinned toolchain> mix quality`: **416 passed**, strict Credo
  clean, Sobelow complete and dependency audit found no vulnerabilities. The
  dependency scanner emits quoted-keyword warnings when parsing the lockfile;
  these are distinct from application compile warnings. An earlier full run found
  one stale exact-map test expectation; evidence/refusal assertions were updated
  and the full gate rerun. Final strengthened TaskTurn/NativeHelper subset:
  **10 passed**.
- Mutation: invert the shared decoder's strict cleanup guard; focused regression
  exits 2. Restored the original bytes before final verification.
- `rtk proxy env PATH=<pinned toolchain> bin/dev.build`: passed, including prod
  warnings-as-errors and strict/deep ad-hoc bundle verification. The build's owned
  executable preflight found no current bundle/release running before replacement.
- `rtk proxy env PATH=<pinned toolchain> bin/smoke`: passed bootstrap/browser
  session/route/origin/heartbeat/graceful-quit/listener cleanup on a disposable fresh
  root, `/private/tmp/ccoding-smoke.V6JeSF`. No saved user workspace was launched.
- Built helper SHA-256:
  `b74b27f88c2dd70487587d29797d80148c367b904a0174bd4a2ef4fc5218e0ed`.
- Diff whitespace and affected local documentation links checked. No migration,
  new dependency, runtime grant, account inference, UI redesign or publication.

RTK proxy preserves exact protocol/native/test/process output and pinned runtime
selection; filtering those streams would obscure statuses or evidence. No raw
process argv/environment was read. User file `Untitled.md.age` remains excluded.
No real-provider interrupted-session, escaped-group, missing-receipt, physical
sleep, signing/notarization or clean-machine acceptance is claimed. The overall
beta goal remains unfinished. Next: retain and reconcile exact provider closure
evidence after restart, without replay or turning an absent process into proof.
