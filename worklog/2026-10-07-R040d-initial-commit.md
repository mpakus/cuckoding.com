# R040d — Initial commit

Claimed clean local main `70ee718`; branch `feature/R040d-initial-commit`.
Acceptance: explicit bounded file preview, exact fresh consent, first local commit
without overwriting working files/index/history, durable interruption, verified
native/browser flow, updated docs and local merge.

Ponytail full 4.13.0 (MIT), local-runner, security-review, LiveView and quality-gates
applied. Reuse R040c ArenaGit/native helper, safe directory identity, command leases,
owned child groups and authenticated disclosure UI. No new plugins or resolved
packages: sha2 0.10.9 was already locked transitively and is now a direct dependency
for preview SHA-256 (verified registry Cargo.toml:39, MIT OR Apache-2.0).
Primary interface references: [hash-object](https://git-scm.com/docs/git-hash-object),
[update-index](https://git-scm.com/docs/git-update-index),
[commit-tree](https://git-scm.com/docs/git-commit-tree) and
[update-ref](https://git-scm.com/docs/git-update-ref). No external source copied.
Git receives fixed argv and buffered approved bytes; no repository filters/hooks,
personal config/author credentials or remote operations. Cuckoding adds scoped
consent, absent-index/ref guards, durable evidence and no uncertain replay.

RTK proxy exceptions: exact native Git protocol experiments, multiline fixture
scripts and isolated package build/smoke environment/stream semantics.

Implementation:
- Explicit selected paths or empty baseline; bounded no-follow reads, single-link
  regular files, file modes/bytes/SHA-256 and config/branch/directory fingerprint.
- Fresh five-minute, Arena/command-scoped consent; duplicate keys cannot substitute
  files. Immutable intent/closed receipt/events reuse six-migration SQLite schema.
- Git creates blobs/tree/zero-parent commit with fixed identity/message; candidate
  index stays private until exclusive publication. Existing index/refs and drift
  refuse. Working documents never change. Interrupted effects never replay.
- Native HEAD/index locks, then packed-ref/branch locks and exclusive link publication.
  No reflog is created. This is a narrow first-commit operation, not general Git
  integration; existing staging/history remains manual. Index/ref/DB are not atomic.
- LiveView preserves path input and hash disclosures, shows raw-byte/ignored-file
  implications, exact author/message, separate consent, elapsed time and Cancel.

Reference investigation: Git v2.54.0 `builtin/update-ref.c:719-730` and
`refs/files-backend.c:2309-2340` (GPL-2.0; verified upstream COPYING) explain why
Git's implicit HEAD reflog update conflicts with explicit HEAD verification.
No Git source copied. Native exclusive loose-ref creation follows the documented
[repository layout](https://git-scm.com/docs/gitrepository-layout), holds HEAD
through publication and cannot replace an existing ref/index. Cuckoding adds
bounded selection, local confirmation and retained uncertain state.

Verification so far:
- `rtk mix format --check-formatted` and `rtk mix quality`: 100 ExUnit tests,
  warnings-as-errors compile, strict Credo and Sobelow pass. Sobelow's lockfile
  parser still emits the existing quoted-keyword warnings; no findings.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`,
  `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`,
  `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: pass,
  31 native tests. Includes real Git selected bytes/empty tree, executable mode,
  nested branch, existing history/index, changed bytes/config/branch/identity,
  symlink/hardlink/FIFO/credential guards, escaped-metadata bounds, foreign lock
  retention and partial staged-index retention. Prior group/deadline checks pass.
- Fixed development failures: unsupported Git transaction (above), inherited
  directory flock across parallel fixture forks (explicit unlock on Git drop),
  and expired-session fixture's pending broadcast (drain before expiration).
  An offline Cargo attempt lacked cached aho-corasick; locked online check passed.
- Browser inspection caught unstyled textarea and disclosure collapse on live
  updates. Reused `role-fields` and `JS.ignore_attributes("open")`; focused
  `rtk mix test test/cuckoding_web/initial_commit_live_test.exs`: 3 passed.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040d-target bin/dev.build`
  passed. Isolated target leaves the user's old running bundle untouched.
  Expected OpenSSL relocation warnings are followed by ad-hoc re-signing.
- Initial packaged smoke passed fresh and prior R040c database copy with unchanged
  source hash, six migrations, retained team/Arena/Tabula/task rows, integrity/FKs,
  auth/replay/origin/heartbeat/graceful Quit and listener cleanup. Browser fixture
  initialization/preview/refused unchecked commit passed. That QA instance was
  stopped by owned BEAM identity, with shell/listener cleanup, before rebuilding
  the UI fixes. Final packaged/browser verification follows below.
- Exact-output Python link check: 22 Markdown files, zero missing relative links.
  `rtk git diff --check` passes. Further evidence and local integration pending.


Final packaged verification:
- Rebuilt the UI fixes with the same isolated `bin/dev.build` command.
  `rtk proxy python3 /private/tmp/cuckoding-r040d-proof-98bgynea/final/verify-package.py`
  passed fresh and prior-copy smoke, integrity/FKs, six migrations and all prior
  configuration/draft rows. The R040c source copy remained byte-identical.
- Bundle: `/private/tmp/cuckoding-r040d-target/release/bundle/macos/Cuckoding.app`.
  Native SHA-256: `2c601742988d80c1f8a2034b803fae4b11f271885bb2b6b9ee34b0fbc75f5532`.
  TabulaLive BEAM SHA-256: `b8c7f89f732794dc617150895a94a2130f5a2cd09625c74a589879f6520e3f4b`.
  Full identity and private QA scripts/results are under
  `/private/tmp/cuckoding-r040d-proof-98bgynea/final/`.
- Browser used a seeded registration and 60-second test-only handoff in that
  isolated DB. Actual UI/native operations performed inspect → confirmed init →
  selected-file preview → confirmed first commit. Registration fixture seeding is
  not a new native-chooser claim; native handoff/security are separately smoke-tested.
- At desktop width 1280 and narrow 390×780 there was no document overflow.
  Input styling, expanded hash through live ticks, keyboard consent/submit and
  reloaded preview/path preservation passed. Confirmation reset on reload.
  Screenshots: `/private/tmp/cuckoding-r040d-preview-final.jpg`,
  `/private/tmp/cuckoding-r040d-narrow.jpg`, `/private/tmp/cuckoding-r040d-completed.jpg`.
- `rtk proxy python3 /private/tmp/cuckoding-r040d-proof-98bgynea/final/verify-browser-result.py`
  passed: sole commit `4575914df4744769e1ebcd70440f37553e03a7d8` contains exact
  `plan.md` bytes; unselected file is preserved/untracked, index matches HEAD,
  no owned Git locks remain, consent/preview/receipt hashes match and 12 events
  contain no paths/content. Packaged restart retained all four commands and the
  single commit without replay.
- QA shell PID 64705 / BEAM 64709 / loopback port 60376 were ownership-checked,
  stopped and verified gone/closed. Temporary browser tab closed; viewport reset.
  The initial listener check ran before startup was ready and was repeated after
  readiness; no unrelated app/process was signalled. The user's running app was
  not replaced or restarted.
- Final `rtk mix quality`: 100 tests, compiler, Credo and Sobelow pass (same
  upstream lockfile-parser warnings). Native source unchanged since 31-test /
  Clippy pass. Final format/diff and Markdown link checks pass.

No public release, push, Pages deployment, clean-machine install, physical sleep
or real-provider execution was tested by this slice. Existing staging/history,
content-level secret detection and richer file selection remain manual. Next app
work: read-only agent planning with file provenance and separate execution grants.
Local main integration follows; this is not remote publication.
