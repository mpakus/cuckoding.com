# R011 · Tidewave UI development

Claimed on clean main cee21d6, feature/R011-tidewave-dev.
Scope: development-only dependencies/endpoint configuration, source-development
launcher preserving bootstrap/session/heartbeat with separate local data, focused
checks and docs. No product execution grant, real account adoption or changes to
the running packaged test app.

Ponytail full 5.1.0 (MIT), LiveView, security-review, local-runner and quality-gates.
RTK proxy is used for exact scripts/source/native output. Primary reference:
https://github.com/tidewave-ai/tidewave_phoenix (Apache-2.0), current manual
installation README and pinned downloaded Hex package source inspected below.
Tidewave exposes developer runtime/code/database capabilities; user explicitly
requested this developer tool. It must be absent from production/test endpoints
and use an isolated development database, not saved provider profiles.

## Implementation and reference evidence

- Hex pins: Tidewave 0.9.1 (Apache-2.0), Phoenix LiveReload 1.7.0 and transitive
  circular_buffer 1.1.0; all previous dependency versions retained. Tidewave package
  checksum: `dc8db03332b35084fd5b5fbe4fcb196c077bbe9cfdf883dcf6a5750a9bc19bb2`.
- `deps/tidewave/lib/tidewave.ex:45-70,88-119,188` owns middleware order, CSP changes
  and external toolbar injection. `deps/phoenix_live_reload/lib/phoenix_live_reload/live_reloader.ex:94-162`
  establishes the inline-script iframe and injection; the exception is restricted
  to that frame in development. No upstream application code was vendored.
- Native release-only startup has no source/code reload; `bin/dev.server` uses
  standard Python facilities to perform the existing shell protocol around a
  source Mix process. Separate marked `.ccoding/ui-dev` data, private environment,
  installed code archives, cooperative native-compatible lock and owned process
  group. One-use launch secrets stay private and are consumed; no user data import.
- Tidewave's local developer MCP intentionally does not require the product
  session. It has trusted host code/DB access; this is not sandboxing or provider
  authorization. Boundary remains ahead of it. Dev/test/prod compile separation,
  current browser-session behavior and the production CSP remain explicit.

## Verification

- `rtk mix deps.get`, `rtk mix format`, `rtk mix compile --warnings-as-errors`: pass.
- `rtk mix quality`: **184 tests passed**, formatting/compiler/Credo/Sobelow/audit
  passed; Sobelow emits its known quoted-keyword lockfile parser warnings.
  The added foundation regression checks dev dependencies/routes/CSP exceptions
  are absent in test. Its first assertion expected a raised 404; corrected to the
  router's actual 404 response before the passing suite.
- `rtk proxy env CCODING_DEV_PARENT_CANARY=must-not-reach-child bin/dev.server --smoke --port 0`:
  pass. Real MCP initialization/tools/evaluation, clean inherited environment,
  app session handoff/replay, toolbar/HEEx/reload injection and CSP, hostile
  Host/origin/cross-site refusal. Fixed a smoke-helper name shadowing its HTTP
  module before the passing run. Initial source startup exposed a missing Phoenix
  Mix listener; adding the standard listener removed that reload warning.
  Initial fresh DB connection logged one transient SQLite lock before readiness;
  subsequent launches and smoke completed without it.
- `rtk proxy bin/dev.build`: pass, production app assembled and signed locally.
  `rtk proxy bin/smoke`: pass for bootstrap, session, replay/origin, heartbeat,
  graceful shutdown and listener cleanup. Retained QA root:
  `/private/tmp/ccoding-smoke.lmj7Vl`.
- Standard-library assertions verified no Tidewave/LiveReload/circular_buffer
  libraries in the packaged production release, no remaining listeners from three
  completed developer runs, second data owner/invalid port refusal and consumed
  launch files. `rtk git diff --check` and changed Markdown link checks passed.
- `rtk proxy bin/dev.server` remains running on loopback **4000**, BEAM PID 60791
  at verification. Chrome visibly rendered the external Tidewave toolbar with
  Sign in/Settings; LiveView navigation to Agents worked. Local-only screenshot:
  `.ccoding/ui-dev/tidewave-toolbar.png`. Original packaged app PID 54794 retained
  its listener on 59652; no restart or profile/data changes to it.

## Delivery and limits

README, AGENTS, Development, Security, Testing and Plan updated in this slice.
Commit/fast-forward local main; no push, deployment or global MCP client edits.
Tidewave account sign-in, paid/provider interaction and a complete interactive
agent edit were not performed. No clean-machine or physical sleep verification;
no Rust source changed, so the Rust suite was not repeated. Existing package
signing/notarization acceptance remains open. The static public site is unchanged.
