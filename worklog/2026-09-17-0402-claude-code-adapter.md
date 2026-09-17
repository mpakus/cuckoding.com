# Worklog — 0402 Claude Code adapter

## Acceptance criteria

- The pinned Claude Code runtime maps the Cuckoding grant into non-interactive permissions and run-scoped instruction, skill, MCP, and settings files.
- Provider output is normalized and redacted, usage/model/session facts remain source-labeled, and cancellation/resume/recovery use the host runner.
- Authentication or isolation failure blocks only Claude sessions; no credentials or user-global memory are copied into a run.
- Fixture conformance passes, with any real smoke opt-in and budget-capped.

## Reference coding

- Project XERJ search: `Claude Code adapter structured output permission mode allowed tools resume session usage config memory`.
- Pinned Hydra MIT search: `Claude provider session resume permission usage process adapter`; inspected its provider discovery/session-resume approach without copying code.
- The repository runtime spike at `spikes/0002-host-runtime/host_runtime_spike.rb:131-235,318-324,390-412` supplies already-reviewed PID/session capture, bounded output, run-scoped config, and reasoning-filter/redaction patterns.
- Installed Claude Code `2.1.142` help and the official headless documentation confirm `--print`, `stream-json`, `--allowedTools`, `dontAsk`, `--strict-mcp-config`, `--resume`, structured output, and the new `--bare` boundary.
- A read-only probe found global OAuth login available, but the same probe with run-scoped `HOME` and `CLAUDE_CONFIG_DIR` is unauthenticated. Official `--bare` mode likewise excludes OAuth and Keychain reads. The adapter must not expose the real home or copy credentials to bypass this boundary.

## Verification

| Check | Result |
| --- | --- |
| `rtk claude --version` | Pass: installed Claude Code `2.1.142`, matching the pinned adapter. |
| `rtk claude --help` and official headless docs | Pass: revalidated bare/print/stream JSON, permissions, strict MCP, structured output, budget, plugin, and resume flags. |
| Global and isolated `rtk claude auth status --json` probes | Global OAuth is logged in; the run-scoped HOME/config probe is not. Only booleans/method category influenced the adapter; account identifiers are not persisted. |
| `rtk mix test test/cuckoding/adapters/claude_code_test.exs` | Pass: 4 tests, 0 failures. |
| `rtk mix quality` (initial) | Functional suite passed: 8 properties, 79 tests. Strict Credo found one nested helper, which was simplified before the final run. |
| `rtk mix quality` (final) | Pass: 8 properties, 79 tests, 0 failures; warnings-as-errors compilation, strict Credo with no findings, Sobelow, and dependency audit passed. |
| `rtk git diff --check` | Pass. |
| Opt-in real provider smoke | Not run: safe bare mode cannot use the machine's global OAuth login, and no separately verified run-scoped `apiKeyHelper` is configured. This is an explicit availability limitation, not a passing smoke. |
| XERJ refresh | Not retried: generation 22 remains sealed but blocked by the node's 95% disk flood-stage watermark; the host filesystem is 99% full and generation 21 remains the last committed index. |

## Work performed

- Added a pinned Claude Code `2.1.142` adapter with version/auth preflight, explicit capabilities, run-scoped settings/instructions/skills/MCP files, and an auditable effective grant.
- Built non-shell argv for `--bare --print --output-format stream-json`, `dontAsk`, explicit allow/deny tools, strict MCP, schema/budget/model selection, and native resume.
- Routed start, cancel, resume, and sleep-gap recovery through the supervised host-runner boundary; continuation fallback remains bounded by the shared contract.
- Normalized init, public activity, tool request/completion, retry, success, and error fixtures; rejected unknown/hidden-reasoning events and redacted summaries, tool metadata, results, and citations.
- Parsed provider-reported token/cost facts with source/confidence and structured knowledge citations.
- Kept global OAuth unavailable to bare runs by design. A host-approved absolute executable helper must exist and a separate run-scoped probe must succeed before the adapter reports authentication.

## Security review

- Provider JSON, tool arguments/results, citations, and auth status are untrusted inputs. Only the pinned closed fixture vocabulary crosses into normalized events; recursive redaction runs before persistence.
- The adapter never invokes a shell, bypass mode, user-global settings, hooks, plugins, MCP configuration, CLAUDE.md discovery, or auto memory. Generated files are owner-only and existing symlink targets are rejected.
- An `apiKeyHelper` path comes only from trusted host options, must be an absolute executable regular file, and is referenced rather than copied. Presence alone never proves authentication.
- Plugin MCP and instruction content comes from the already-approved immutable plugin snapshot. Filesystem, network, and resource claims the runtime cannot prove are recorded under `unenforced`.
- Residual risk is the documented trusted-host boundary: provider subprocesses run as the local user. A real smoke remains unavailable until run-scoped authentication exists; no production-ready claim is made from fixture evidence alone.
