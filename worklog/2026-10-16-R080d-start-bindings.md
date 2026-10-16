# R080d — Start binding repair

2026-10-16. Owner: Codex. Ponytail full 5.2.0 (MIT), local LiveView,
workflow-and-kanban, security-review and quality-gates instructions applied.

## Acceptance and diagnosis

Explain the exact missing role choice, preserve explicit submitted choices, link
to the correct editor and verify repair through existing guarded save/adoption/
Start operations. No automatic model choice, account substitution, inference,
Arena execution, historical rewrite or relaxed admission.

Started clean on local main `01396c1` (37 commits ahead of origin/main).
Read-only saved SQLite inspection found Beta team revision 6 selected c2 for
Speculator/Secutor with blank model IDs. Start classified a blank model as
`agent_unassigned` and linked to the provider rather than Team. Team's shared
merge also discarded a submitted model when the submitted agent differed from
the server draft, including Save/recovered submissions. Later explicit c2/Cursor
Disconnect commands created unassigned current revisions 9–11 and cleared their
catalogs; preserve those newer user actions. No credentials were inspected.

`rtk proxy` is used for exact source reads, SQLite JSON, tooling and artifact
checks because filtered output would obscure protocol/verification evidence.

## Verification

- `rtk proxy env PATH=<pinned toolchain> mix test
  test/cuckoding_web/team_live_test.exs test/cuckoding_web/battle_live_test.exs
  test/cuckoding_web/team_adoption_live_test.exs`: 37 passed, repeated after the
  final missing-model label simplification. Covers a Save without preceding
  change, blank-model warning, forged catalog ID refusal, explicit adoption,
  reconnect and fixture Start. Existing guarded session/revision tests pass.
- `rtk proxy env PATH=<pinned toolchain> mix quality`: 372 tests passed;
  format/compile, Credo, Sobelow and dependency audit passed. Sobelow emits its
  existing quoted-keyword warnings while parsing the lockfile. No vulnerabilities.
- Final `mix format --check-formatted` and `rtk proxy git diff --check` passed.
- `rtk proxy env PATH=<pinned toolchain> bin/dev.build`: passed. Initial cleanup
  encountered a newly appeared `.DS_Store` in generated release output; inspection
  found no remaining app processes and only that generated metadata file. Repeating
  the unchanged build succeeded. No data directory or build script was changed.
- `rtk proxy bin/smoke`: passed bundled launch, bootstrap/cookie, handoff replay/
  origin refusal, heartbeat, normal quit and listener cleanup. Isolated evidence:
  `/private/tmp/ccoding-smoke.92te3I`.

Pinned toolchain PATH:
`/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
No Rust source, migration or JS changes; native build compiled successfully,
separate Rust lint/unit suites were not repeated. Real provider usage, real Arena
execution, narrow-browser and timed release acceptance were not run.

## Preserved workspace / running artifact

Verified idle SQLite state, integrity/FKs, backend executable/parent/start/cwd and
loopback listener before the documented unavailable-tray fallback. Private online
backup: `.ccoding/r080d-validation/before-rebuild.sqlite3` (0600, ignored).
Audit-token-bound normal SIGTERM to backend 83645 let it exit normally, then shell
83643 exited via heartbeat; port 55149 closed. No escalation. This fallback does
not record a tray `shell.quit_requested` event.

Reopened the exact saved `Open Cuckoding Test.command`, retaining
`/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`. New native/backend PIDs
90215/90217, listener `127.0.0.1:56507`. Compared the backup: all 14 non-session
state tables and 275 preexisting events unchanged; integrity/FKs passed. All 73
assembled/bundled ebin artifacts match. These identities are dated observations.

Native Chrome read-only walkthrough verified Home's disconnected state, Team's
incomplete-role warning, Beta's two retained task cards, and Beta's Edit roles
link reaching `/team#role-speculator`. No settings saved and no Start clicked.
Both current connections remain disconnected by the user's later explicit
actions. Real Beta needs reconnection, explicit role/model choices and board-team
adoption; this patch does not silently undo those actions.

## Integration

Implementation committed as `62d4a94`, fast-forward merged to local main;
`fix/r080d-start-bindings` deleted after merge. Docs/AGENTS/README updated in the
same implementation commit. This follow-up records verified integration. No push
or publication. The running bundle contains the verified source implementation;
the final task/worklog integration note does not change executable code.
