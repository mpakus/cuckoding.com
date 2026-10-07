# R040f — Selected document planning

Claimed by Codex on `feature/r040f-document-planning` from clean local main
`999cf7e` (12 commits ahead of the saved remote reference). Task acceptance is
in [R040f](../tasks/R040f-document-planning.md). No remote publication authorized.

## Inspection and approach

Reviewed the current contexts, seven migrations, LiveView components, dispatcher,
native helper and Codex transport against the architecture/flow/security docs.
The shipped boundary is setup and draft planning, not autonomous execution.
SQLite owns commands, observations, team adoptions and drafts; the dispatcher
serializes bounded operations. No new scheduler, database table or dependency is
needed for selected document snapshots.

Reuse repository source at `999cf7e` (Apache-2.0):
`desktop/src-tauri/src/arena_git/initial.rs:69` descriptor-relative file reads,
`lib/cuckoding/arena_git.ex:130` scoped command/receipt lifecycle,
`lib/cuckoding/planning.ex:57` frozen planning request, and
`desktop/src-tauri/src/connection/model_check.rs` restrictive structured turn.
The adapted boundary reads only explicitly selected files locally; the provider
receives bounded text snapshots, never an Arena filesystem grant.
Ponytail full 4.13.0 (MIT) and repository architecture, workflow, security,
LiveView, local-runner, adapter and quality-gate skills applied.

`rtk proxy` exceptions: exact source/document reads, editing scripts and native
build/QA scripts need unfiltered output/exit semantics. Product Git/provider
commands remain unwrapped fixed declarations.

## Verification

- `rtk mix test test/cuckoding/planning_test.exs test/cuckoding_web/planning_live_test.exs test/cuckoding_web/team_adoption_live_test.exs` — 11 passed during implementation.
- `rtk mix test test/cuckoding/planning_documents_test.exs test/cuckoding_web/planning_live_test.exs` — 8 passed.
- `rtk mix quality` — final 122 tests passed; format, compiler warnings-as-errors,
  Credo, Sobelow and dependency audit passed. Initial Credo nesting/complexity
  findings were fixed by extracting enqueue/receipt validation; a subsequent
  unused assignment warning was removed. Sobelow still emits the documented
  Elixir 1.20 generated-lockfile keyword warnings; no vulnerabilities found.
- `rtk mix test test/cuckoding_web/planning_live_test.exs` — 5 passed after the
  browser-discovered disclosure fix. Final full quality also includes that fix.
- `rtk mix test test/cuckoding/planning_documents_test.exs` — 3 passed after
  strengthening the foreign-scope assertion to use a still-fresh snapshot.
- `rtk mix format --check-formatted` — passed after that test refinement.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040f-target cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked` — 33 passed. Native fixtures
  prove explicit selection, no Git mutation, directory identity, traversal,
  symlinks, hardlinks, FIFO, invalid text, byte/total limits, hashes and restricted
  structured input. Existing cancellation/descendant/grant checks pass.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check` — passed.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040f-target cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings` — passed.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040f-target bin/dev.build`
  — final isolated bundle built. The owned QA app was stopped before rebuilding
  the disclosure fix. Default/user bundles were not overwritten or restarted.
- `rtk proxy python3 /private/tmp/cuckoding-r040f-proof-2bl9icb7/release-smoke/verify-package.py`
  — final bundle fresh/prior-copy smoke passed, seven migrations, integrity `ok`,
  no FK violations, exact prior data retained, original fixture DB hash unchanged.
  An earlier smoke overlapped the previous build's completion; it is superseded
  by this post-build proof. No schema change was introduced.
- `rtk proxy python3 /private/tmp/cuckoding-r040f-proof-2bl9icb7/start-browser.py`,
  `connect-browser.py`, `snapshot-stop.py`, `restart-browser.py`, `verify-final.py`
  — isolated fixture setup, metadata-only ownership/listener inspection and
  restart verification. Exact commands, snapshots, proposals, draft revisions,
  prior events and import linkage survived; no replay or live user DB was involved.
- `rtk proxy python3 - <<'PY'` local Markdown-link and fixture-canary assertions
  — all README/AGENTS/docs file links resolve; selected source text and unselected
  canary are absent from app logs/audit events. No project Git directory appeared.
- `rtk git diff --check` — passed.

## Packaged browser evidence

CUA on the default desktop viewport and 390 × 844 verified local preview, exact
text/hash, separate missing-consent refusal, frozen source despite editing the
fixture file after preview, successful structured proposal from the local protocol
stub and once-only import into Specs. Unsaved manual draft and brief survived
updates; selection changes cleared consent. Reconnect/restart retained evidence
without silently selecting it for another request. The source disclosure initially
collapsed during a LiveView patch; stable IDs/ignored `open` now preserve it through
validation and live updates. Narrow document width stayed 390 px with no page
horizontal overflow. Viewport reset and temporary CUA tab closed.

Screenshots: `/private/tmp/cuckoding-r040f-documents.jpg` and
`/private/tmp/cuckoding-r040f-narrow.jpg`.

Final artifact:
`/private/tmp/cuckoding-r040f-target/release/bundle/macos/Cuckoding.app`.
Final tested shell/BEAM/listener: `11715` / `11723` / `127.0.0.1:51177`, stopped
with verified cleanup. Earlier QA `10669` / `10674` / `50925` also stopped.
The user/default app was not replaced. Retained synthetic evidence and scripts:
`/private/tmp/cuckoding-r040f-proof-2bl9icb7/`.

- Native SHA-256: `2326f13a70d9bb619f50c7adc7e9ee3c85a986add1cd719841fa36022cd114b1`
- PlanningDocuments BEAM: `1f7be15d67729352b3a128e91bc48afa16e594ce0131143085471cfb2241a79d`
- Planning BEAM: `b36c41cef42c871af047d637d0856ee22a079a538075097e8db4daeff7c2e351`
- PlanningComponent BEAM: `215af00c1d2c7b07e4f0f2aeadc88af18c30ff3cd3c21140e9537a0a2fc169d3`

## Audit conclusion and remaining work

The existing contexts, SQLite ledger and native reader cover this slice without
new tables, dependencies or generic orchestration infrastructure. Architecture
now maps actual source ownership separately from target workers/records. AGENTS
replaces accumulated slice narration with boundary rules and authoritative links;
README, workflow, data, security, UI, adapters, development and checklist agree.

Successful inference here is explicitly a local protocol fixture, not a real
signed-in provider. No personal credentials were read or provider usage started.
Human-completed login/real turns, accepted Markdown specs, validated per-task
citations, dependencies/custom workflows, execution grants, autonomous review
loops, parallelism, physical sleep and release signing remain open. Site was not
changed; no site gates, remote push or deployment were performed.

## Local integration

`fc5a7c1` (`feat(planning): Preview selected documents for Speculator`) was
fast-forward merged into local `main` with
`rtk git merge --ff-only feature/r040f-document-planning` after verification.
`rtk git branch -d feature/r040f-document-planning` deleted the merged branch.
This entry records actual local integration. No remote push or Pages deployment
occurred; the isolated native proof bundle is built and stopped, not the running
user application. Documentation link targets/heading anchors and
`rtk git diff --check` passed before integration.
