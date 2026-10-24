# R100c — Verified pre-migration backups

Completed on `feature/R100c-upgrade-backups`, base `872dfa7`; local-main integration only.
Ponytail full 5.3.2 MIT; OTP/LiveView, migration, menubar, security and quality
guidance. No provider usage, user workspace/profile access or publication.
`Untitled.md.age` stays unread and unstaged.

Database currently applies known migrations before dispatch but relies on manual
backups. D053 adds a verified restore point before an existing schema changes.
Native/source launchers already share the workspace shell lock. Keep fresh and
current-schema starts fast, retain all partial artifacts and never infer cleanup
or restore authorization from a backup.

Official [SQLite VACUUM INTO](https://www.sqlite.org/lang_vacuum.html) documents
consistent copies, interrupted-copy risk and synchronization under NORMAL/FULL.
The installed Exqlite source supplies readonly validation and the existing Repo
query primitive. OTP 28.5 kernel `file.erl:1424` documents directory open mode;
a disposable local probe verified directory sync. No upstream implementation is
copied and no new dependency/runtime is required. Exact-output commands use RTK proxy.

## Result and review

`Database.migrate!/2` checks future/unknown schemas, then calls `UpgradeBackup`
before existing-schema migration. Fresh/current databases need no copy. The
launcher remains the exclusive owner; authentication, dispatch, HTTP and readiness
still follow Database. There is no new supervisor, native command or provider grant.

The copy uses parameterized `VACUUM INTO`, source/copy integrity/FKs/exact schema,
readonly DBConnection checks, a 1 GiB bound, shared 20-second query/hash budget,
streamed SHA-256 and file/directory sync. Exclusive UUID artifacts and immutable
receipts precede the atomic fixed pointer. Failed/partial attempts are retained.
OS I/O is not an absolute hard deadline; the unchanged shell readiness ceiling
still applies. A copy is not a downgrade/restore permission or native cleanup proof.

Path review found that Storage's earlier chmod pass could touch a hardlinked
database before the backup guard. Storage now refuses linked/special private
files before chmod and validates the marker's exact size/type/link count before
reading. Its focused regressions preserve the linked file's original mode.
The marker and metadata share bounded descriptor-checked reads in UpgradeBackup;
no global analysis suppression was added. Fixed-path annotations follow the
existing Storage convention. Settings keeps its normal LiveView/session boundary,
renders only dated whitelisted metadata and has no restore/download control.

Self-review covered correctness, finite work, failure preservation, source and
copy identity, native/source startup order, private output scope, immutable copies,
parameterized SQL, no account access, and existing component/disclosure behavior.
No unresolved actionable issue remained in this slice. The change is split into
storage/tests `b548d59`, Settings/tests `ccc3ec1`, and documentation/evidence.

## Verification

- Red focused tests failed at the missing migration/backup boundary before code.
- `rtk proxy env PATH=<pinned> mix test test/cuckoding/upgrade_backup_test.exs
  test/cuckoding_web/upgrade_backup_live_test.exs`: **12 passed**, final log
  `.ccoding/r100c-focused-final.log`. Covers WAL rows, readonly unchanged backup,
  exact hash/schema/modes, no repeated current/fresh work, unknown/future schemas,
  malformed/linked pointer, hardlinked source/marker, oversized marker, failed
  FKs/durability and a later failing migration that preserves the verified old DB.
- A plain-file-copy mutation failed the one WAL regression as expected; source
  restored in `finally`. The first filter selected zero tests and was discarded;
  the corrected exact test produced one failure. `.ccoding/r100c-mutation.log`.
- `rtk proxy env PATH=<pinned> mix quality`: **605 passed**, warnings-as-errors
  compilation, strict Credo **2249 mods/funs, no issues**, Sobelow and both Hex
  checks passed. `.ccoding/r100c-quality-final.log`. Runtime migration module
  redefinition and dependency-audit quoted-keyword warnings remain tool noise;
  no application compilation warning or advisory was suppressed.
- `rtk proxy env PATH=<pinned> cargo test --manifest-path
  desktop/src-tauri/Cargo.toml --locked build_info`: **1 passed**;
  `.ccoding/r100c-native-metadata.log`. Native behavior is unchanged; the whole
  Rust suite was not rerun for this BEAM/storage slice.
- `rtk proxy env PATH=<pinned> bin/dev.build`: passed, including strict/deep
  ad-hoc seal and private build receipt. `.ccoding/r100c-build-final.log`.
- `rtk proxy env PATH=<pinned> bin/smoke`: passed fresh packaged authentication,
  protected routes, handoff/origin refusal, heartbeat, graceful Quit and listener
  cleanup. `.ccoding/r100c-smoke-final.log`; root
  `/private/tmp/ccoding-smoke.ZH5KDZ`.
- The same final packaged `Contents/MacOS/ccoding --smoke-test`, with explicit
  `CCODING_RELEASE_DIR` and disposable `CCODING_DATA_DIR`, passed the copied
  schema-17 upgrade and current-schema restart; linked-backup startup exited 1
  before authorization/migration with the exact sanitized backup refusal.
  `.ccoding/r100c-{upgrade,refused,restart}-smoke-final.log`.

The `<pinned>` PATH is Elixir 1.20.3 OTP28 / Homebrew OTP28.5 / Rust1.97.1:
`/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.

## Actual final artifact and data evidence

Final bundle: `desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`.
Build **`6a847ba5-58b1-4305-9da2-edf75dcce6e6`**, source `ccc3ec1` with a dirty
observation; schema18, Elixir1.20.3, OTP28.5, Rust1.97.1. The application input
digest matches the completed checkout. Private immutable receipt:
`.ccoding/build-receipts/6a847ba5-58b1-4305-9da2-edf75dcce6e6.json`.

- Input SHA-256: `77158b8a5d5c9b70a06cca6829a5608cb8942f7715607a7d72459994a498f166`.
- Helper SHA-256: `85b52ab6496803215f4c518bace753c4126bedbe6e6268aade9126af93ce438a`.
- Resource manifest SHA-256: `9aa96db21d9cf923897719a5070468180ccd68e2b0e021f8a645870b0eb2b13c`.

Only fresh private fixtures under `/private/tmp/cuckoding-r100c-0_4tueg5` were
used. Source was the retained disposable R060r `before-upgrade.db`, never a user
workspace/profile. `sealed-upgrade` advances17→18, while its verified copy at
`backups/4529e0d3-af39-439f-9a13-8f701c223b4c/foundation.db` remains17 with all
**16 prior tables identical**, valid integrity/FKs, exact SHA/modes/root binding.
The working DB preserves prior facts; only four expected authentication/power/Quit
events and ephemeral browser tokens change. The refused DB remains17 with every
original row identical and its linked destination empty. Restart preserves the
same receipt, pointer, hash and backup entries. Locks are released and no owned
smoke process/listener remains. No user app is left running.

Docs/AGENTS/README reflect the implemented scope. The broader R100 backup/import,
coordinated restore, signed updater/rollback, clean-machine and physical power-loss
gates remain open. Real provider usage, full native recovery and ten-minute human
acceptance were not run. No push, publication, reset, provider login or inference.
Final `git diff --check` and 262 local Markdown targets passed; source input digest
still matches the sealed artifact after documentation updates.
