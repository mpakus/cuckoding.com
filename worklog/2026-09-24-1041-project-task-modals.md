# 1041 — Project task forms in LiveView modals

Claimed task 1041 on a clean main checkout; branch
`feature/1041-project-task-modals`. Acceptance: two board action buttons, reusable
LiveView form/modals, retained input and visible validation, accessible dismissal
and focus, responsive layout, current docs and focused verification.

Read the required product, architecture, database, flow, security and execution
contracts, BoardLive and its form callers/tests. Applied Ponytail 4.10.0 (MIT),
project LiveView and quality-gates skills, and better-accessibility.
Existing audit/domain commands remain authoritative; opening/cancelling a form
does not write workflow state. No schema or provider-launch changes.

No existing dialog component was found. XERJ has no listener on port 9200, so no
indexed retrieval is claimed. Reused the installed MIT Phoenix LiveView pattern
at `deps/phoenix_live_view/lib/phoenix_live_view/js.ex:1052-1076` to preserve a
native dialog's `open` attribute across patches, with the existing application
hook registration pattern. Native dialog behavior was checked against
[MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog).
No peer implementation was copied. RTK proxy exceptions: complete source reads
and exact scripted verification/setup where filtered output would lose semantics.

## Implementation and checks

The two buttons open one transiently selected native dialog through a shared
Phoenix function component. BoardLive's two form components reuse the existing
domain commands. `phx-change` retains draft values across periodic updates and
dismissal; task success clears the form and closes it. Task validation has its
own error, so a rejected card move no longer opens an unrelated task form.
Opening/closing writes no workflow events; successful creation still records
the existing durable task event. No dependency, schema, provider or policy change.

- `rtk env -u CR_PAT mix test test/cuckoding_web/board_live_test.exs test/cuckoding/board_task_intake_test.exs`:
  19 tests, 0 failures, initially and after the final error-focus change.
- `rtk env -u CR_PAT mix quality`: formatter, unused-dependency check,
  warnings-as-errors compilation, 10 properties and 335 tests passed. Stopped
  at Credo for a missing module doc on the new component; added the doc.
- `rtk mix credo --strict`, `rtk env MIX_ENV=test mix sobelow --config`,
  `rtk env -u CR_PAT mix hex.audit`, `rtk mix format --check-formatted` and
  `rtk env MIX_ENV=test mix compile --warnings-as-errors`: passed afterward.
  Formatter/compiler/Credo/Sobelow were repeated after the final focus change;
  the focused suite covered that change without repeating the full suite.
- `rtk env -u CR_PAT mix assets.build`: passed, including the final template.
- `rtk node test/task_board_motion_test.cjs`: passed; hook registration retains
  the existing board behavior.
- `rtk proxy python3` link validation over all six changed Markdown files:
  local Markdown targets exist. `rtk git diff --check`: passed.

## Rendered verification

`rtk env -u CR_PAT mix run --no-start tmp/1041-ui/preview.exs` started an isolated
safe-mode development preview at loopback port 4114, with its own SQLite file
under `tmp/1041-ui/`. It used synthetic project/role data, no saved provider
account and no native application data. Initial SQLite pool connections retried
a transient startup lock; the preview then started successfully. Read-only
integrity and foreign-key checks passed afterward; no run was created.
Local-runner and security-review guidance informed preview scope and cleanup.

Browser checks exercised both buttons and forms at desktop, 390px and 320px:

- Title/planning-prompt initial focus, native modal semantics, background absent
  from the accessibility tree, keyboard traversal without reaching background
  controls, Escape and Cancel with focus returned to the correct button.
- Draft values retained after closing/reopening and across several five-second
  updates, with textarea focus unchanged. One development source reload reset
  the transient form as expected; the tick check was repeated without edits.
- Whitespace task-title validation remained in the modal; correcting it created
  a Draft card, closed/reset the form, restored focus and announced success.
  The card survived a development reload. Planning configuration failure kept
  the entered prompt and visible error; successful planning navigation/import
  is covered by the focused integration test, not a real provider session.
- Both narrow widths had document width equal to viewport width and modal
  scroll width equal to client width. At 320px, a new error initially landed
  below the visible dialog area. Added LiveView `JS.focus()` on alert mount;
  the final browser check confirmed the alert focused and fully scrolled into
  view. Dialog scrolling keeps the submit action reachable.

The browser recorded four `MutationObserver.observe` errors during initial
loads/development reloads, with no source URL. Neither the application assets,
LiveView client nor live-reload source contain a MutationObserver invocation.
No attribution to product code is claimed; all modal interactions above passed.

The supplied native URL was blocked by the browser tool, so verification used
the isolated preview. No authentication bypass was attempted. The viewport was
reset and preview tab closed. `rtk lsof -nP -iTCP:4114 -sTCP:LISTEN`, metadata-only
`rtk proxy ps -p 61311 -o pid=,ppid=,comm=,lstart=` and
`rtk lsof -a -p 61311 -d cwd -Fn` identified the preview's BEAM process started
at 11:19:03. `rtk proxy kill -TERM 61311` stopped it gracefully; its command
exited 0 and the port had no listener.
This signal is another exact-semantics RTK proxy exception.

## Delivery state

Working-tree implementation on `feature/1041-project-task-modals`; no main
integration, remote publication, Pages deployment, native bundle rebuild or
native restart. Existing native application data/processes were untouched.
The current native app must be rebuilt/restarted to display this source change.

## Sidebar motto follow-up

Continuing the same UI task with the user's follow-up. Preserve the exact text
`Made in Austin☆Texas with Irony and Sarcasm.` immediately above
`Local-first. Human-guided.` in the shared LiveView layout. The existing public
site credit at `github.page/index.html:167` confirms `https://aomega.co` as the
author website. Reuse the sidebar footnote typography and responsive behavior;
open the external link in a new tab to retain the application page.

Added the link using the existing `workspace-footnote` class, centered and
underlined, with `target="_blank"` and `rel="noopener noreferrer"`. The global
focus style still applies; the existing mobile footer-hiding rule is retained.
No CSS, dependencies or new test files were needed for this copy/link change.

- `rtk env -u CR_PAT mix test test/cuckoding_web/board_live_test.exs`: 11 tests,
  0 failures.
- `rtk mix format --check-formatted`, `rtk env -u CR_PAT mix assets.build`,
  `rtk env MIX_ENV=test mix compile --warnings-as-errors`,
  `rtk mix credo --strict`, `rtk env MIX_ENV=test mix sobelow --config` and
  `rtk git diff --check`: passed.
- The rendered-component structural check below passed for exact copy, URL,
  new-tab attributes and footer order. The first two harness attempts used
  `--no-start` and failed because `render_component` requires a module context
  and verified routes require a started endpoint. Running in a module with the
  test application started resolved both; no product fix was needed.

```sh
rtk env MIX_ENV=test mix run -e 'defmodule VerifySidebar do; require Phoenix.LiveViewTest; def run do; html = Phoenix.LiveViewTest.render_component(&CuckodingWeb.Layouts.app/1, inner_block: []); doc = LazyHTML.from_document(html); link = LazyHTML.query(doc, "header.workspace-sidebar > p.workspace-footnote > a[href=\"https://aomega.co\"][target=\"_blank\"][rel=\"noopener noreferrer\"]"); true = String.trim(LazyHTML.text(link)) == "Made in Austin☆Texas with Irony and Sarcasm."; footer = LazyHTML.query(doc, "header.workspace-sidebar > p.workspace-footnote"); true = LazyHTML.text(footer) =~ ~r/Made in Austin☆Texas with Irony and Sarcasm\.\s*◇\s*Local-first\. Human-guided\./; IO.puts("Rendered sidebar: exact motto, website, safe external link and footer order passed"); end; end; VerifySidebar.run()'
```

This follow-up is verified source only; the native build/restart remains pending.

## Requested main integration and native restart

The user authorized local main integration and app restart. Acceptance: merge
the verified task/modal and sidebar changes, rebuild the native bundle, stop
only the owned shell through its supported SIGTERM shutdown path, preserve
native data and verify one healthy replacement shell/control-plane pair.
Applied menubar-shell, local-runner, security-review and quality-gates guidance.
The dirty file inventory contains only this task's changes; main is an ancestor.

Fresh metadata identifies the exact repository bundle's shell PID 46977
(started 10:55:57 local) and child PID 47061 (10:55:58), listening on
`127.0.0.1:64301`. Inspection uses executable paths, parents/start identities,
cwd and listeners, never argv or environment. A first `ps` listing put `comm`
before another field and truncated it; placing `comm` last confirmed the paths.
Read-only SQLite checks: integrity `ok`, no foreign-key violations, one project,
one board, one task, no runs/processes, two saved provider accounts, and exactly
the checked-in migration set. No migration or provider access is required.
