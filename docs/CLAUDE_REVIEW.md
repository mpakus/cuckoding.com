# Claude in managed review

In a task's workflow form, choose **Claude** as reviewer and enter the trusted
check command, then **Start workflow**. Codex still plans and implements/fixes.
Both local CLI accounts may incur usage charges. The existing manual Codex
run/check/review flow is unchanged. Restart BOSS to apply pending migrations.

Admission stores the selected reviewer before effects. It cannot change during
execution or retries: the same command UUID with a different reviewer conflicts.
Older deliveries remain Codex. Historical labels use the stored reviewer, not
the current form. Claude failure does not fall back to Codex or start a paid retry.

## Evidence and execution boundary

Each review starts a fresh Claude CLI in an exclusively created private scratch
directory. stdin carries the immutable original spec, typed plan, complete diff
from original base to candidate, check configuration/receipt, complete bounded
check stdout/stderr and prior feedback. Input is capped at 1 MiB without truncation.
Candidate identity/tree are checked before and after review as for Codex.

If the target advanced, explicit **Integrate approved result** invokes the saved
reviewer again on a new merge candidate and may incur additional charges. Claude
also receives the complete current-target diff, original approval identity and
new check evidence. The original approval cannot authorize the new merge; there
is no automatic review retry after target drift or rejection.

Claude assesses this supplied evidence only. `--tools ""`, `dontAsk`, disabled
slash commands, empty strict MCP configuration and an MCP deny rule remove model
filesystem/shell/MCP tools. The internal `StructuredOutput` formatter remains
available for the schema response. Ordinary hooks and automatic memory are
disabled, user/project/local settings sources are empty, and session persistence
is disabled. Existing local authentication is retained; BOSS does not read auth
files or use `--bare`, `bypassPermissions` or an implicit provider fallback.

This is a CLI permission boundary, not an OS sandbox. Administrator-managed
startup policy/hooks can override ordinary settings suppression. Empty settings
sources do not isolate every global CLI configuration. Do not describe this mode
as full host isolation or as Claude inspecting repository files.

## Result and transport

Streamed text, tool payloads, session/account identifiers and raw errors are not
persisted. Only bounded event types/counts/usage and the validated typed review
report enter receipts. The final `result.structured_output` is authoritative;
intermediate formatter calls and a success/exit message alone are insufficient.
The report must satisfy the existing strict schema and exactly cover the saved
plan's acceptance criteria. Unexpected tools, denied permissions, malformed or
truncated output and failed terminal results cannot approve a candidate.

The same native macOS guardian owns the process group. A normal exit0, both
actual EOFs, known group cleanup and valid protocol/report are all required.
Stop, output/time limits, missing receipts and Repo loss keep the existing
failure/quarantine rules. An implementation approval leads to Ready. A fresh
integration approval authorizes only its exact merge candidate; publication and
postchecks are still required for Done.

## Compatibility evidence

Local help/version inspection found the required flags in Claude Code2.1.142.
Finite fake-CLI tests exercise the protocol and BOSS transport. This does not
establish actual provider authentication, model access or paid end-to-end success;
real provider acceptance remains a separate opt-in step. Claude planning and
implementation, Linux execution and arbitrary model/role configuration are not
included in this increment.

Sources consulted: [CLI reference](https://code.claude.com/docs/en/cli-reference),
[headless execution](https://code.claude.com/docs/en/headless),
[StructuredOutput protocol](https://code.claude.com/docs/en/agent-sdk/structured-outputs#recognize-the-structuredoutput-tool-call),
[hook settings](https://code.claude.com/docs/en/settings-reference#disableallhooks),
[settings-source limits](https://code.claude.com/docs/en/agent-sdk/claude-code-features#what-settingsources-does-not-control).
