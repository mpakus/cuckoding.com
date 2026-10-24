# R050n — Frozen image and protected check control

Verified locally on `feature/R050n-frozen-check-image`, base `ae7b73c`.
Previous goal turn made progress: production candidate transport and packaged
protocol/recovery checks passed. Next implement the image/runtime that consumes it.

Ponytail full5.3.2 MIT, native runner/architecture/security/quality guidance.
Use RTK, no user profiles/workspace changes, no provider usage or publication.
Leave `Untitled.md.age` unread and unstaged. No subagents are authorized.

Implemented the production native image installer and guest programs; no VM
launcher, virtualization entitlement, battle policy or ordinary startup download
was added. Fixed CLI requests install/inspect under private
`runtime-home/check-images/<UUID>`. Inputs are 24 compiled official HTTPS assets
with exact size/SHA256 and retained license/version metadata. No arbitrary URL,
destination, executable or toolchain can be supplied. The installer owns a
300-second UTC/monotonic budget; fixed curl/tar process groups close before results.
Missing/changed/replayed artifacts refuse without repair. Descriptor-relative
exclusive files, private modes, original intent/receipt and current storage
identity bind verification. Partial downloads/images remain retained.

Archive composition uses flate2 1.1.10, tar 0.4.46 (no default xattrs) and zip
9.0.5 (deflate only), not a new general archive decoder. Six required packages
were added to Cargo.lock; unrelated resolver edge changes were restored and the
locked build passed. TAR/ZIP paths, types, collisions, entry/file/aggregate sizes
are checked in memory, with no host extraction; setuid/setgid bits are stripped.
The fixed kernel comes from the hashed ISO through a pinned stdin descriptor.
The image spec hashes its inputs and producer/guest source; full kernel/ramdisk
hashes and the manifest stay separate from that spec digest. The caller must
retain the exact original public image receipt, not discover new authority from
an arbitrary matching file pair.

Guest PID1 mounts a fixed environment and owns a 320-second watchdog outside the
worker group. Root control validates exact check/candidate manifests and original
source bytes/modes, then starts only npm/Mix with bounded literal argv. The worker
joins the nondelegated group before dropping to UID/GID1000, no capabilities and
no-new-privileges: 128 PIDs, 512MiB/no swap, one CPU and finite file/descriptor
limits. There are no network/share devices, user profiles or provider credentials.
Only root can access the console/control files. Captured worker output is data,
bounded to 64KiB with exact count/hash; overflow refuses rather than producing a
truncated passing result. Group closure and source integrity precede a typed
bound result. A future production keeper must still require actual native Stopped
and exact frozen OTP authority. The current check normalizer rejects both new
contracts, even in an otherwise valid legacy success envelope.

The first actual VM attempt failed with normalized `control_failed` before worker
launch, while native Stopped still verified. The controller unnecessarily checked
both runtimes during npm setup with a five-second cold BEAM limit. It now checks
only the selected runtime and gives the fixed Mix version probe fifteen seconds;
normalized phase/errno diagnostics were added. Subsequent npm/Mix checks pass.
Cold BEAM timeout was the likely original cause, not independently established
by that first generic error. Failed fixtures remain retained, without replay.

Verification uses the pinned Elixir1.20.3/OTP28.5, Rust1.97.1 and Swift6.4 toolchains.
Commands are RTK-prefixed; private logs live at `.ccoding/r050n-*`.

- `rtk proxy mix quality`: 615 tests passed, formatting/compilation/static checks,
  Hex/audit and Sobelow passed. Existing migration-drill module redefinition and
  lockfile keyword warnings remain, with no suppression. A later test-only
  contract-refusal assertion passed in all three focused BattleChecks tests.
- `rtk proxy cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  118 passed, seven opt-in cases ignored. All seven new native image cases pass,
  including exclusive/link-safe files, scope replacement, forged/missing receipt,
  exact cancellation, traversal/special entries/collisions, concatenated gzip,
  deterministic newc/modes, ZIP paths and malformed kernel offsets. The first new
  test compile needed an explicit usize index; final full compilation/tests pass.
- Rust format and locked all-targets Clippy with `-D warnings` passed. Node's three
  production protocol/descriptor tests passed. Python AST validation passed.
- `rtk proxy cargo audit --file desktop/src-tauri/Cargo.lock`: exit0, 433 packages,
  no vulnerability errors, **eight warnings**, not a clean-warning claim. The new
  archive packages have no reported advisory. Existing Tokio1.53.2 is affected by
  RUSTSEC-2026-0386 (patched1.53.3); other existing maintenance/unsoundness warnings
  are RUSTSEC-2024-0370/0429 and 2025-0075/0080/0081/0098/0100. The native dependency
  follow-up is explicit in PLAN before release. No advisory was suppressed.
- Actual debug-helper production image install/inspection and nine VM cases passed
  in `/private/tmp/cuckoding-r050n-run-zu8mebtt`, key
  `a14c1e4c-cb6a-409d-b7cb-7559c701d41d`; npm/Mix pass/fail, denied console plus
  forged output, source-link mutation, timeout, invalid scope and active EOF
  cancellation. Each accepted check requires group closure and actual SDK Stopped;
  cancellation never invents a check result. These are synthetic fixtures, not
  real-project or production-keeper acceptance.
- `rtk proxy bin/dev.build` passed, sealing the local-preview app with strict/deep
  verification and private receipt `03bb8249-8a4f-4d4c-8242-4b1283bef9d5`.
- `rtk proxy python3 -B test/check_input_smoke.py`: all nine operations passed with
  the new sealed helper in `/private/tmp/cuckoding-r050m-cli-mdwwx6yi`; original
  source/index and repeated-read evidence remain intact, tamper/missing proof refuse.

The test-only SDK observer adds a separate image mode; it is not shipped or a new
entitlement. Low scratch space was handled only through byte-preserving APFS
clones of exact pinned inputs/identical VM prefixes and removal of confirmed idle,
owned regenerable compiler caches. Hashes were checked before/after; image,
candidate, receipt and failed-fixture contents remain intact. No user data or
uncertain artifacts were deleted. The guest test uses copy-on-write fixtures to
avoid duplicating the same 76MB image prefix for each case.

Primary sources: [tar sequential/concatenated archive API](https://docs.rs/tar/0.4.46/tar/struct.Archive.html),
[flate2 MultiGzDecoder](https://docs.rs/flate2/latest/flate2/read/struct.MultiGzDecoder.html),
[Node child-process API](https://nodejs.org/api/child_process.html),
[Tokio advisory](https://rustsec.org/advisories/RUSTSEC-2026-0386.html).

No real account usage/sign-in, actual Arena,
personal profile, provider parallelism, physical sleep, clean-machine install,
Developer ID/notarization, licensing/distribution or keeper-loss recovery is
claimed.

The sealed helper passed the production image installer/inspection, replay and
foreign-receipt refusals, extra-argument rejection and all eleven actual VM cases
in `/private/tmp/cuckoding-r050n-run-65o3_wk9`. In addition to the debug cases,
60KB output passes and oversized output produces `output_limit`, empty retained
bytes and the observed oversized count, never a truncated pass. Every case has
an actual SDK Stopped observation. Private `evidence.json` SHA256:
`9b61e28f788fc588d9f452fe9b497871461c416009671d1826fc21a49e2674e9`.

| Sealed observation | Value |
| --- | --- |
| Build | `03bb8249-8a4f-4d4c-8242-4b1283bef9d5` |
| Source input SHA256 | `1c963f18a5d59729bd449202c7436c0054da9565fe579acdaedbcc908f13f879` |
| Native helper SHA256 | `c8973428dc927da39b8888f25bd465a8ae80dbcf15a2393a60249d16057e8dee` |
| Sealed resource manifest SHA256 | `371d46ea80338339cb49b99788ff370cbbb4bc8b03dc834ac02fb8c94beac024` |
| Image key | `a2c77908-1fea-476f-bf8b-a625af8c1d45` |
| Image spec SHA256 | `5775a9f2433b9cbfb19fa002d7a604e88576909b422e7998c26bed420735374b` |
| Kernel SHA256 | `256d5fff4bb892edcb9218c1e6353e388bc3646e65f76c2bc9d958b635d1b00e` |
| Ramdisk SHA256 | `6627500cb9d785d634acc4c322c7016e8860c5ffe257977c910c548ebad055fc` |

The image has 5,396 entries/175,997,524 expanded bytes and a 76,868,626-byte
ramdisk. This is a dirty-base local-preview/ad-hoc build with schema18; source
digest and strict/deep seal were verified. No distribution acceptance is implied.

`rtk proxy python3 -B test/packaged_recovery_smoke.py` passed both current sealed
release/OTP cases: complete proof in
`/private/tmp/cuckoding-packaged-recovery-f2gvgcol` reaches Paused/Secutor; absent
proof in `/private/tmp/cuckoding-packaged-recovery-tpo8uz3l` remains Needs attention/
Combine. Claims, budgets, head and artifacts stay intact; repeated restarts never
Resume or replay, and graceful shutdown/lifecycle/refusal/deadline checks pass.
These fixtures contain explicitly synthetic provider history, not account evidence.

`rtk proxy python3 -B test/guest_lifetime_probe.py` reran all five original SDK
modes in `/private/tmp/cuckoding-r050j-68p3e0ip`: input/EOF/deadline/paused shutdown
verify; owner loss still has no cleanup receipt and remains unverified. The
observer is compiled from the current changed Swift source, not reused old code.

The first R050k regression in `/private/tmp/cuckoding-r050k-st5c887q` passed PID
and memory pressure, but strict EOF verification failed because fork-exhaustion
stderr interleaved its prefix with the diagnostic session line. The line contained
the expected cgroup and native shutdown still verified; the parser was not weakened.
The test worker now waits for its session diagnostic to complete before pressure.
`rtk proxy python3 -B test/guest_lifetime_probe.py --watchdog` then passed all four
modes in `/private/tmp/cuckoding-r050k-79_mxr_c`, with unchanged limits/denial checks.
Hard keeper loss still has no native cleanup receipt and remains explicitly
unverified. The failed fixture and its actual logs remain intact.

Final checks verified 285 relative Markdown file links, Python ASTs, formatting,
the exact current sealed source digest/helper hash and strict/deep signature.
Only intended task paths are staged; the unrelated encrypted file stays unread
and unstaged. Local integration is to main only; there is no push/publication or
real saved-workspace launch.

Review traced fixed CLI callers, download process ownership, archive parsing,
private descriptor/receipt binding, guest privilege/resource/output separation,
literal command bounds, cleanup/source checks and legacy grant refusal. No
unresolved defect was found in this image/runtime slice. Real keeper/Start
integration and the recorded dependency/release gates remain open.
