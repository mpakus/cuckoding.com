# R103 — Patch the native Tokio cohort

Verified locally on `fix/R103-native-tokio`, base `dd60fc5`.
The previous goal turn made progress: production image/runtime code and actual
sealed-helper VM checks merged as R050n. Its audit identified this compatible
native dependency patch as release follow-up.

Ponytail full5.3.2 (MIT), Rust router/ecosystem, security and quality guidance.
Use RTK throughout; no subagents, inference, user profiles/data roots or publishing.
Keep `Untitled.md.age` unread, untouched and unstaged.

Authoritative sources:
[RustSec RUSTSEC-2026-0386](https://rustsec.org/advisories/RUSTSEC-2026-0386.html),
[Tokio1.53.3 release](https://github.com/tokio-rs/tokio/releases/tag/tokio-1.53.3).
They identify 1.53.3 as a patched compatible cohort. Do not claim that updating
the lockfile alone establishes runtime/release acceptance.

`cargo update -p tokio --precise 1.53.3` changed only the Tokio version/checksum
in Cargo.lock. Its direct parent remains Tauri2.11.5. There is no added direct
dependency, application source/API edit, feature change or schema/grant change.
Repository native code has no Tokio AsyncFd caller to migrate.

Fresh unsuppressed JSON/human audits report zero vulnerability-class errors and
seven warnings. RUSTSEC-2026-0386 is absent. The advisory database contains1,352
advisories at `8a5b8090ef20c9c1b425f3373f28b0b23cc5c7a0`.
For `--target aarch64-apple-darwin -e normal,build`, `glib`0.18.5's unsoundness
warning and `proc-macro-error`1.0.4's maintenance warning are absent from the
resolved target graph. Five `unic-*`0.9.0 maintenance warnings remain through
urlpattern0.3.0/Tauri utils in both build/runtime dependencies. No warning was
suppressed, no replacement fork was forced and target absence is not a release
waiver. Their upgrade/replacement or explicit release disposition remains in PLAN.

Verification with RTK and pinned Rust1.97.1/Elixir1.20.3/OTP28.5:

- `rtk proxy cargo audit --file desktop/src-tauri/Cargo.lock [--json]`: exit0,
  433 packages, the seven warnings above. Private `.ccoding/r103-audit*` records
  include the exact database and warning observations.
- Locked `cargo tree -i tokio` and normal/build target graph: one patched Tokio,
  unchanged Tauri parent; metadata resolves without lock drift.
- `cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check` and locked
  all-targets Clippy with `-D warnings`: passed.
- `cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: 118 passed,
  seven opt-in tests ignored. This includes process cleanup, cancellation, private
  paths, provider fixtures, native Git/recovery and fixed image tests.
- `rtk proxy bin/dev.build`: rebuilt/sealed the complete local preview. Ordinary
  vendor relocation warnings were followed by re-signing and strict/deep seal
  verification. No release bundle or backend was active before replacement.
- The rebuilt helper's `--build-info` matches the current source digest. Its
  read-only `--verify-check-image` verified R050n's original full image receipt
  in `/private/tmp/cuckoding-r050n-run-65o3_wk9`, preserving the spec/full hashes
  and retained artifacts. This run boots no VM and grants no execution authority.

| Sealed artifact observation | Value |
| --- | --- |
| Build | `d2bb6f4d-142f-43b4-bc4d-5cf6975bb248` |
| Source input SHA256 | `f92dc54c61a1e92485617a5c476845f00d24f5324691622a9d8291dfab19ffe6` |
| Helper SHA256 | `88e941861853e63be2e734b5dbf410c46964707c63f89cb673f442c0b0109552` |
| Resource manifest SHA256 | `8878d24e97632faabde030e03d096d51d4c26cf70138f0d9c898f68db5d1a079` |

The build records dirty base `dd60fc5`, schema18, Apple Silicon and local-preview/
ad-hoc status. Packaging/inspection is not notarization, dependency provenance,
clean-machine, real-account, physical sleep or full beta acceptance. The full
Elixir suite and guest boot matrix were not rerun for this lock-only patch;
their R050n results remain historical. Packaged recovery results follow below.

Review confirms one compatible dependency patch, no unrelated resolver changes,
no new authority/data access or advisory suppression, and preserved public claims.
The next implementation boundary is still the production VM keeper plus frozen
OTP/Start integration. Do not enable guest checks from this maintenance patch.

`rtk proxy python3 -B test/packaged_recovery_smoke.py` exited0. Complete proof in
`/private/tmp/cuckoding-packaged-recovery-tbqt3geo` reaches Paused/Secutor; absent
proof in `/private/tmp/cuckoding-packaged-recovery-plrp_3ix` remains Needs attention/
Combine. Claims/history/budgets/head/source/proof stay intact, a second boot
never resumes or replays, and graceful shutdown passes. Its fixed ninety-second
timeout in `/private/tmp/cuckoding-packaged-recovery-ik0pj6wa` and input/EOF/
populated/linked-root refusal lifecycle checks pass. The final summary binds the
current build/helper, retained at `.ccoding/r103-packaged-recovery.json`; no stale
summary was used as current evidence while the test process was still running.

Final structural verification checked 244 relative Markdown file links, the
single-package lock diff, current source/helper hashes and strict/deep seal.
Only this task's paths enter the local-main commit; the encrypted unrelated file
remains unread/unstaged. No push, publication or actual saved-workspace launch.
