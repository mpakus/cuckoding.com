# R070c — Attempt-bound receipt validation

Claimed from local main `42dc9a3` on `feature/r070c-stage-receipts`.
Ponytail full, architecture, workflow, security and quality guidance apply.
RTK proxy preserves exact source/test/build output. The user's untracked
`Untitled.md.age` remains unread and untouched.

`Battles` currently combines 1,500 lines of durable controls/transitions and
receipt parsing. Parallel tasks need one validator bound to an immutable attempt,
without copying the sequential coordinator's current-task cursor. This slice
extracts the existing validation boundary before adding task-lane state.
No execution policy, stored record, migration, provider usage or UI changes.

## Review and checks

The 163-line predicate block was compared with the prior committed source after
normalizing only visibility/function names/format whitespace: unchanged. The
original result-field list and hash predicate moved with it. Every caller was
traced; cancellation retains bound+payload validation, provider closure alone
retains its explicit extra field, and the coordinator retains write authority.
No orphaned path or duplicated validator remains.

- New contract tests first failed because the module was absent (2 failures).
  The first extracted focused run exposed a remaining retry-path `TaskTurn` alias;
  the alias was restored. Corrected focused battle/executor/contract suite: 113
  passed.
- Mutation: removing the closed-field check accepted the raw provider canary;
  contract test failed (exit 2). Exact source restored in `finally`.
- `rtk proxy env PATH=<pinned toolchains> mix quality`: 457 passed in 22.4 s; strict
  Credo/Sobelow and both dependency audits passed. Sobelow's existing lockfile
  quoted-keyword warnings remain. One DB client-exit log appeared during the suite;
  no test failed.
- `rtk proxy env PATH=<pinned toolchains> bin/dev.build`: production compile,
  release/native bundle and strict/deep ad-hoc signature verification passed.
- Eight affected Markdown files' local links and `git diff --check` passed.

No native/JS/UI behavior changed, so the just-completed R070b native suite (94
passed, 5 opt-in ignored) was not repeated. No browser, real provider, task-lane,
physical sleep, signing/notarization or clean-machine acceptance inferred.

- Final `rtk proxy env PATH=<pinned toolchains> bin/smoke`: passed bundled launch,
  bootstrap/session/route checks, replay/origin refusal, heartbeat, graceful Quit
  and listener cleanup. Disposable data: `/private/tmp/ccoding-smoke.sM4zYz`.
  Packaged helper SHA-256:
  `f4e7a991476b0a1261308b5453867118a1dc47febed6575be40ed668fe5d716c`.

Integration: verified slice committed and merged into local main; branch deleted.
No push/publication or real workspace launch. Task-lane implementation follows.
