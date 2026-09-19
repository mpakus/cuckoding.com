# Worklog — 1009 web startup PubSub order

## Acceptance criteria

Start PubSub before recovery workers, preserve reconciliation behavior, and run the development web server on loopback.

## Baseline

- Branch: `fix/1009-web-startup-pubsub`
- Preserved unrelated task 1005 website edits, task 1008 files, `icon.png`, and `workspaces/`.
- Reproduction: `rtk mix phx.server` exited while reconciling an active run because `EventStore` broadcast to `Cuckoding.PubSub` before that registry was started.
- Mandatory Ponytail full mode and local-runner, security-review, and quality-gate guidance loaded.

## Implementation

- Moved `Cuckoding.PubSub` before runtime children so startup reconciliation can publish committed activity events.
- No runner, credential, network, or persistence policy changed.

## Verification

- `rtk mix format --check-formatted` — passed.
- `rtk mix compile --warnings-as-errors` — passed.
- `rtk mix test test/cuckoding/reconciler_test.exs` — 1 property and 6 tests passed.
- `rtk mix test` — 10 properties and 236 tests passed.
- `rtk mix credo --strict` — 193 files checked; no issues.
- `rtk mix sobelow --config` — scan complete with no findings.
- `rtk node --check github.page/script.js` — passed.
- `rtk ruby github.page/verify.rb` — 14 local references and 4 pinned actions verified.
- `rtk git diff --check` — passed.
- Credential-pattern scan — no matches in repository files outside generated workspaces.
- `rtk proxy env -u CR_PAT PHX_SERVER=true mix phx.server` — started on `127.0.0.1:4000` against the existing active-run database.
- `rtk curl http://127.0.0.1:4000/` — HTTP 200.
- Browser smoke check — dashboard rendered projects, operations, activity, and usage; the tab was left open for testing.

## Security note

Process inspection exposed a GitHub credential inherited from the user's shell. It was not copied into the repository, and the running web server was launched with `CR_PAT` removed. The credential still needs to be revoked or rotated and removed from shell startup configuration.
