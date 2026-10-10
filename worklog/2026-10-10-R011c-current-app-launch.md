# R011c · Current app launch recovery

## Acceptance and diagnosis

Restore Arenas and the existing Agents/Team flow, preserving saved setup. The
reported listener 64913 belongs to BEAM 72823 / shell 72822, started 2026-10-10
15:32:01 local. `lsof` identifies the obsolete generated `CCoding.app` bundle,
with data in `~/Library/Application Support/CCoding Rebuild` at schema 1.
Current source and the separate `Cuckoding.app` bundle retain the roster/wizard,
Team editor and Arenas. The earlier test workspace at
`/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data` has schema 9, one named agent
record plus legacy workspace connection, two team revisions and two Arenas.
Its previous listener 59652 is no longer running.

Clean starting point: main at 6453097, seven commits ahead of origin/main.
Scope: native packaged smoke, launch artifacts, README/AGENTS/development docs.
No agent, Team or Arena product behavior needs reverting. Do not migrate/merge
the unrelated foundation-only database into the saved test workspace.

Ponytail full (5.1.0, MIT), menubar-shell, local-runner, security-review and
quality-gates apply. `rtk proxy` preserves exact process identity, source/script,
SQLite inspection and native build output. No argv/environment dumps or provider
credential reads. The tray-only app could not be addressed through computer-use
accessibility (timeout); use the owned BEAM's graceful termination if needed and
verify shell/listener cleanup.

## Changes and verification

- Verified the old PID/start/executable/parent identities immediately before
  SIGTERM to its owned BEAM. OTP shut down, the shell exited on its heartbeat,
  and listener 64913 disappeared. No unrelated process was signalled.
- SQLite backup API under the free shell locks retained both databases at
  `/private/tmp/cuckoding-r011c-recovery/{saved-workspace,old-foundation}.db`.
  Integrity and foreign-key checks passed. The obsolete generated app moved to
  `.ccoding/retired-builds/CCoding.app.retired`; its database stayed untouched.
- Updated ten existing test command launchers to the current repository bundle,
  keeping the original data path. Added an ignored local convenience launcher
  `.ccoding/Open Cuckoding Test.command`. Reused the existing native launch/stop
  harness rather than inventing another application launcher.
- Extended `Service.smoke_browser` to check session redirects and authenticated
  Agents/Add agent, Team/Add role, Arenas and Settings pages. No application
  behavior, provider binding, database schema or Arena UI was changed.
- `rtk mix test test/cuckoding_web/agents_live_test.exs
  test/cuckoding_web/team_live_test.exs test/cuckoding_web/arena_live_test.exs
  test/cuckoding_web/tabula_live_test.exs`: **23 passed**.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked
  --all-targets -- -D warnings`: passed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  **49 passed**.
- `rtk proxy bin/dev.build`: passed. Hex still reports the pre-existing Decimal
  3.1.1 advisory EEF-CVE-2026-97853 / GHSA-6c27-994x-c52f; no dependency change is
  included in this recovery.
- `rtk proxy bin/smoke`: passed with the expanded route checks, native bootstrap,
  browser session, replay/origin refusal, heartbeat and graceful cleanup.
  Isolated smoke data: `/private/tmp/ccoding-smoke.4OEYkZ`.

## Actually running artifact and browser evidence

Current bundle: `desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`.
Native shell 88438 / BEAM 88440 opened `http://127.0.0.1:51617` with the original
test data at `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`. Dated PID/start,
bundle hash and launcher records are in `/private/tmp/cuckoding-r011c-recovery`;
these are evidence, not future process identities.

In the actual authenticated Chrome session:

- Agents shows saved signed-in Codex (one selected model) and Cursor (seven).
- Add agent opens the four-step wizard with connection name and runtime picker.
- Team retains revision 2 and all four required roles. Speculator's expanded
  editor retains Codex/GPT-6.1-Sol. Add role created an unsaved custom role;
  selecting Cursor populated all seven saved Grok options and selecting Grok 4.6
  worked. Discard/reload removed only that temporary draft, without saving.
- Arenas shows the two retained projects. Opening Ura Mawashi shows its Beta
  board and two existing draft cards, with the R002 Advanced layout.
- Left the current browser on Agents. Screenshot retained as
  `/private/tmp/cuckoding-r011c-recovery/restored-agents.png`.

After launch/UI checks, all 12 retained database tables match the backup
(existing events match as a prefix). Only the expected `shell.authorized` and
`browser.authorized` events and browser-session tokens were added. Integrity and
foreign keys pass. The first comparison correctly detected those new events;
the subsequent comparison explicitly verified the retained prefix instead of
mistaking launch audit records for data loss.

`rtk git diff --check` and changed Markdown reference validation passed. Commit
and merge into local main; no push or deployment. The current app remains running.

## Limits

No provider sign-in, refresh or inference was repeated; saved setup and UI controls
were verified. No full Elixir quality rerun (no Elixir changes); focused LiveView
checks and native checks/build/smoke passed. Autonomous Start is still pending as
before. The existing test workspace remains at its original `/private/tmp` path;
this recovery intentionally does not relocate private profiles or absolute
worktree/artifact references. Durable test-data relocation needs a separate
verified migration. Existing backups and launchers are retained.
