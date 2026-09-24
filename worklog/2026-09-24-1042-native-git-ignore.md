# 1042 — Honor host Git ignores in native repository checks

Claimed on clean main (`995e586`), branch `fix/1042-native-git-ignore`.
Acceptance: match normal Git ignore behavior in the native app, retain real
dirty-repository rejection and repository overrides, keep credentials/hooks
isolated, add focused regressions/docs and verify the replacement native build.

Read the existing task's required product/architecture/database/flow/security/
execution docs and relevant GitService callers. Applied Ponytail full,
local-runner, security-review, quality-gates and menubar-shell guidance.

Read-only reproduction on the registered echobeyond.com repository:
`/usr/bin/git status --porcelain --untracked-files=all` is empty under the normal
home; with the native app-owned home it reports only `.DS_Store` and
`docs/.DS_Store`. The user's effective `core.excludesFile` is their global
`.gitignore`, absent from the native environment. No user file was changed,
stashed, committed, reset or deleted. The source repository was also clean.

RTK proxy exceptions: complete source reads; exact read-only subprocess status
comparison with separate stdout/stderr and a source-derived app-home value.
No process arguments, environment dumps or credentials were inspected.

## Implementation and reference

GitService's shared Git helper now queries only the effective `core.excludesFile`
using the host-home hint, then passes just that path as a Git command option.
Repository overrides/tilde paths and the XDG fallback follow Git's own parser.
Actual commands retain the app-owned HOME. Configuration lookup errors fail
closed without displaying config contents. Existing workflow audit events stay
unchanged; no new permission, database, agent environment or policy snapshot.

Local reference: `git_service.ex:718` shared Git command helper;
`desktop/src-tauri/src/main.rs:151-152,231-232` host hint and isolated HOME;
`local_process_runner_test.exs:32-52` hint exclusion from child environments.
XERJ has no listener on loopback 9200, so no indexed retrieval is claimed.
No peer code copied. Verified behavior against the primary
[Git ignore documentation](https://git-scm.com/docs/gitignore) and
[Git configuration documentation](https://git-scm.com/docs/git-config).

Initial focused command:
`rtk env -u CR_PAT mix test test/cuckoding/execution/git_service_test.exs test/cuckoding/board_task_intake_test.exs test/cuckoding/execution/local_process_runner_test.exs`:
29 tests, 0 failures. New regressions cover base capture, worktree creation and
inspection, tracked/untracked protection, repository override, default ignore
location and a sentinel proving the host's fsmonitor hook is not imported.
Added malformed-config fail-closed and empty-XDG coverage afterward.

## Quality and actual-repository check

`rtk env -u CR_PAT mix quality`: final pass, 10 properties and 337 tests,
0 failures; formatter, dependency lock check, warnings-as-errors compiler,
strict Credo, Sobelow and dependency advisory audit all passed. This includes
the existing path, process cleanup, port, sleep/recovery and secret/hint
exclusion regressions. The first full run caught a test expecting the internal
config error instead of the existing public repository-validation error, plus
Credo nesting depth. Corrected that assertion and used function clauses to
flatten the helper, then reran the entire command successfully.

`rtk git diff --check` and an exact `rtk proxy python3` local Markdown link/path
check passed. No UI, assets or schema changes require additional UI testing.

Read-only check of the user's actual repository, with native app HOME and host
hint set only within the test process, passed without an application start:

```sh
rtk env -u CR_PAT MIX_ENV=test mix run --no-start -e 'System.put_env("CUCKODING_RUNTIME_HOME", "/Users/mpak"); System.put_env("HOME", "/Users/mpak/Library/Application Support/com.cuckoding.desktop"); {:ok, {_repo, _sha}} = Cuckoding.Execution.GitService.validate_repository("/Users/mpak/www/echobeyond.com", "main"); IO.puts("Actual registered repository passes with native app HOME and host ignore lookup")'
```

Fresh native inventory still identifies shell 22591 (11:53:48 local), child
22680 (11:53:49) and only listener 127.0.0.1:51789. Read-only native integrity
and foreign keys pass: 1 project, 1 board, 2 tasks, 0 runs/processes, 2 saved
provider accounts. The failed planning attempt's task is retained. No user
repository or task data is changed by the fix/verification.
