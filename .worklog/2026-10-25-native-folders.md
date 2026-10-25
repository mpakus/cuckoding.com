# 2026-10-25 — native folder selection

- Request: select repository folders using OS UI, without typing paths.
- Baseline: main d3b9d84, clean checkout; isolated branch codex/boss-native-folders.
  Parent owns implementation/docs; a separate read-only agent researches/reviews.
- Continue RTK, Ponytail, TDD, reference coding and browser/native verification.
- xerj query `openDirectory` found Backlog desktop workspace-picker.ts:71 and
  main.ts:219 at 3580cfbbb1be4144a5cca5b49190e1f8158e4cf7. Adopt native directory
  selection, explicit cancellation and server validation after selection. Do not
  add Electron solely for a picker or treat browser file uploads as local paths.
- This user correction supersedes the earlier plan to delay a native folder
  picker until a desktop wrapper. Preserve local session/CSRF/origin protection.

## Implementation and source evidence

- `Boss.FolderPicker`: supervised, asynchronous native process, one caller at a
  time, two-minute deadline, bounded output, caller monitor and explicit helper
  termination. macOS fixed AppleScript receives title/path as argv; Linux uses
  Zenity argv in a graphical session. No shell interpolation or new runtime deps.
- Followed Apple's official choose-folder/argv examples and Elixir Port lifecycle
  documentation: closing a Port alone does not guarantee child termination.
  Sources: https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/PromptforaFileorFolder.html
  and https://hexdocs.pm/elixir/Port.html. No reference implementation copied.
- Agetor `src/bun/refs-endpoint.test.ts` and native chooser in `src/bun/server.ts`
  at fbd68603afef778a618a94ca88e0c00997956afd also informed auth/cancel/error
  boundaries. Rejected a browser-upload surrogate and Electron solely for a picker.
- LiveView holds chosen folders server-side. The form accepts only name/base
  branch from the browser; paths are readonly and forged path parameters ignored.
  Specs stays relative where possible, preserving existing Git canonicalization
  and the lstat-based no-symlink/no-escape validation.
- Parent owns all edits; folder_picker_review agent performed independent read-only
  research, review and final recheck. No overlapping writer/docs changes.
- Changed picker/supervision, HomeLive, helper/UI tests, README, AGENTS, plan/todo
  and worklogs. No migration, provider call, production runner or source spec edit.

## Verification

- `rtk proxy asdf exec mix test test/boss/folder_picker_test.exs test/boss_web/project_live_test.exs`:
  initial 7 helper tests passed and 4 UI tests failed against the old typed form;
  implementation made all 11 pass. A fifth UI test was added during review.
- Review found (1) trimming all newlines could select the wrong Linux folder,
  (2) relative specs default was resolved from BOSS cwd. Fixed both. The newline
  regression failed against the original implementation and passed after changing
  to removal of exactly one record delimiter. Specs test asserts default/changed
  chooser initial dirs and registration through macOS /var canonicalization.
- `rtk proxy asdf exec mix test`: 39 passed. Tests include cancel/error preservation,
  forged paths, repo boundary, busy response, timeout, caller death and shutdown
  actually terminating fixture OS processes. No desktop dialog in automated tests.
- `rtk proxy asdf exec mix compile --warnings-as-errors`, `mix format --check-formatted`,
  `mix assets.setup`, `mix assets.build`, `mix assets.deploy` all passed through
  RTK/asdf. Fresh dependency build retains upstream Plug's xref deprecation warning.
- Temporary server on 127.0.0.1:4320 with exclusive scratch data: browser login,
  disabled initial actions and real native request observed. Browser subsequently
  displayed the actual macOS chooser's returned repository path in the readonly
  field and enabled Add project. That selected repository was not registered or
  edited. CUA cannot target the osascript app, so scripted native selection/Cancel
  and complete real-dialog lifecycle acceptance are not claimed. Linux GUI untested.
- Screenshot: external task artifact `boss-native-folders.png`, showing the new
  buttons and readonly paths. No credentials or raw private transcripts retained
  in repository logs. Existing unrelated app/browser activity was left alone.
- Final independent review: both findings resolved, no remaining blockers found.
  Separate Git/runner spike results remain prior-increment evidence; unchanged.

## Outcome / next step

- Implementation 513f991 merged into local main as b67e8b3. Combined main checks:
  39 application tests, compile --warnings-as-errors, format --check-formatted,
  assets.deploy passed through RTK/asdf. A previously running BOSS must be
  restarted to start the newly supervised picker. No remote push performed.
- Stopped only the owned port-4320 server; confirmed port closed, removed its
  exclusive scratch data/repo and closed its browser tab. Existing server untouched.
- The app rejected worktree archival: "The task's primary checkout cannot be
  removed." Reattachment did not resolve it; attaching the source main checkout
  was rejected because it is not managed. No forced removal. Detached the clean
  worktree at main and safely deleted the merged codex branch. The managed
  boss-native-folders worktree remains attached until the app can release it.
- Next product increment remains BOSS-002b spec identity/revisions, then importer;
  Linux desktop/native-dialog automation acceptance remains a separate open gate.
