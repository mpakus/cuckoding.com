# Worklog — 0803 reference plugins

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 0803
- Status: complete
- Human/agent owner: codex
- Branch: `feature/0803-reference-plugins`
- Start revision: `91e04ec`
- End revision: task commit

## Acceptance criteria

- Ship valid bundled manifests and contract implementations for RTK, Ponytail,
  XERJ, and one generic MCP server.
- Validate RTK's underlying command before wrapping and label analytics as estimates.
- Enforce Ponytail's stage scope and non-negotiable policy overlay.
- Derive XERJ namespaces from durable server-side IDs and degrade cleanly when unavailable.
- Pin a maintained MCP implementation exactly with integrity evidence, declared
  permissions, and a tool allowlist.
- Show labeled plugin contributions on run detail and preserve core behavior
  when binaries disappear.

## Reference coding

- Focused project, Vibe Kanban, and Agetor XERJ searches were attempted first;
  the configured loopback node was unavailable.
- Pinned Apache-2.0 Vibe Kanban's adapter mapping at
  `crates/executors/src/mcp_config.rs:390-430` informed one canonical MCP
  configuration translated per runtime; no source was copied.
- Pinned MIT Agetor's credential-free MCP descriptions and scoped discovery at
  `src/bun/commands.ts:380-420,610-682` informed the visible, run-scoped
  configuration boundary; no source was copied.
- The official Model Context Protocol filesystem server repository and npm
  registry were checked on 2026-09-18. Version `2026.8.31` is current and
  maintained; npm reported integrity
  `sha512-kKaFkyAh6oipvc9+EAbJ552JafnMnOq5nzmzWkp1jJdBhTAAGpmIpWihUG1+rfNhmEFM98gUZDdCHCDD4v6a7Q==`.
  The archived/deprecated GitHub reference server was removed from the example.
- The reviewed Ponytail 4.10.0 `SKILL.md` is MIT licensed; its upstream SHA-256
  is `1316a2f3f95741d2300b116fe0c2d81ce4a9568656ed0a62643f54aaf09957f2`.

## Work performed

- Claimed Task 0803 and restated its acceptance criteria.
- Added four strict bundled manifests with binary/file detection and no automatic enablement.
- Added RTK policy-first wrapping, streaming passthrough, and separately persisted estimated analytics.
- Added the reviewed Ponytail instruction package with exact stage scope,
  `lite`/`full` modes, and a non-waivable quality and safety overlay.
- Added bounded XERJ configuration with durable server-derived project
  namespaces; caller-supplied namespace text is ignored.
- Added the exact-version, integrity-recorded official filesystem MCP package
  with offline configuration and a read-only tool allowlist.
- Added source-labeled run-detail contributions and removed the obsolete
  floating archived GitHub MCP example.
- Added regression coverage for relative plugin-file detection, prefixed
  prerelease version output, fake-binary enablement, reference behavior, and
  missing-binary degradation.

## Verification

| Check | Result |
| --- | --- |
| Focused manifest, registry, reference-plugin, and run-detail tests | pass; 11 tests, 0 failures |
| `rtk mix credo --strict` | pass; 156 source files, 2,394 functions/macros, no issues |
| Actual installed-tool discovery | pass; RTK, Ponytail, XERJ, and npx prerequisites all reported available; no manifest errors |
| `rtk mix quality` | pass; 10 properties and 173 tests, 0 failures; Credo checked 156 files/2,394 functions and macros with no issues; Sobelow and dependency audit passed |
| `rtk git diff --check` | pass |

## Handoff

Task complete after the final diff check and local-main merge. The MCP package
is configured offline and exactly pinned; populating its verified cache remains
a separate reviewed installation action rather than a side effect of discovery.
