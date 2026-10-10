# R011b · Remove Tidewave

User requested removal after the integration did not meet their needs. Claimed on
clean main b728149, fix/R011b-remove-tidewave. Ponytail full 5.1.0 (MIT), LiveView,
security-review and quality-gates; RTK proxy for exact scripts/source output.

Scope: remove the installed development dependency, its transitive circular_buffer,
endpoint mount and toolbar/MCP launcher smoke expectations; retain standard Phoenix
reload and the normal shell handshake. Update current guidance and mark the prior
task superseded without rewriting historical evidence or deleting private data.
No developer listener on port 4000 or owner of the private developer lock at start.

## Change and verification

Removed Tidewave from Mix deps/lock, deleted its downloaded dependency and compiled
build through `rtk mix deps.clean tidewave circular_buffer --unlock`, and removed
its endpoint plug. No global integration was installed by R011. Existing private
recordings stay ignored/preserved, with historical task evidence marked superseded.

The developer smoke now asserts removed GET/POST MCP and config/connect routes
return 404; HTML has no toolbar/assets and application CSP has no external origin,
inline/eval permission or framing. Phoenix LiveReload's own iframe needs inline
script and same-origin framing; that narrow dev-only response now sets those
directly, without relying on Tidewave's global removal of framing protection.
Test/prod retain their ordinary CSP and no reload iframe route.

- `rtk mix format` and `rtk mix quality`: pass; 184 tests, compiler, Credo, Sobelow
  and dependency audit. Known Sobelow quoted-keyword parser warnings remain.
- `rtk proxy python3 test/dev_server_test.py`: one passing lock lifecycle regression.
- `rtk proxy bin/dev.server --smoke --port 0`: pass on 64037; bootstrap/session,
  one-use handoff, reload annotations/iframe headers, host/origin refusals,
  strict application CSP and removed Tidewave routes/assets verified.
- Dependency source/build absence, Markdown links, syntax and
  `rtk git diff --check`: pass. Smoke listener closed and no developer owner left;
  existing data retained. No new long-lived preview launched.

Updated README, AGENTS, Development, Plan, Security and Testing. Commit and merge
local main; no push/publication. Browser interaction, provider usage, native rebuild
and Rust tests were not repeated for this development-only dependency removal.
