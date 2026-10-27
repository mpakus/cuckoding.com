# Claude reviewer adapter — 2026-10-27

Baseline c7f7fc0, branch codex/boss-claude-review. Scope: managed review only;
Codex still plans/implements. Root owns reviewer admission/schema/docs.

Research: xerj bossrefs query `structured_output` returned an unrelated SVG;
rg fallback located examples/backlog/packages/core/src/claude-executor.ts:124–196
and claude-executor.test.ts. Pinned SHA
3580cfbbb1be4144a5cca5b49190e1f8158e4cf7 verified, Apache-2.0 LICENSE.
Adopt stream-json result-event separation and terminal usage allowlisting.
Reject bypassPermissions, prompts in argv, raw output logs, silent malformed
line skipping and legacy result fallbacks. No reference code copied.

Design: Claude no-tool reviewer receives full bounded saved evidence via stdin.
Current CLI flags researched by independent researcher; native guardian owns
exit/EOF/Stop/cleanup. Typed structured output is separate from protocol success.
No provider calls or auth-file reads. Implementation and verification pending.

Implementation commits20c0fed and00872d5:
- Managed reviewer selection only; Codex planning/implementation and manual
  attempts unchanged. Missing selected Claude fails before any paid Codex stage;
  stage-time lookup still refuses disappearance, without fallback.
- Native guardian handles Claude stdin, bounded JSONL, EOF/exit/Stop and cleanup.
  Fresh exclusive private cwd prevents repository discovery. Cleanup is attempted
  after a known receipt; unknown ownership/worker death can retain scratch.
- CLI args suppress ordinary settings/hooks/auto-memory/MCP/skills/session storage
  and external tools. Only internal StructuredOutput may appear. Managed policy
  startup hooks cannot be promised disabled; this is not an OS sandbox. BOSS
  does not read auth files or change account mode with --bare.
- Final result.structured_output stays transient until clean protocol/process
  completion and existing strict report validation, including duplicate keys and
  plan coverage. Explicit failure/refusal/truncation/deferred reasons fail closed.
  Only bounded event kinds/counts/bytes/usage and validated report are persisted.

Official references (read by researcher and implementation review):
- https://code.claude.com/docs/en/cli-reference
- https://code.claude.com/docs/en/agent-sdk/structured-outputs
- https://code.claude.com/docs/en/agent-sdk/typescript#sdkratelimitevent
- https://code.claude.com/docs/en/settings-reference#disableallhooks
- https://code.claude.com/docs/en/agent-sdk/claude-code-features
- Published SDK0.3.220 sdk.d.ts TerminalReason union supplied explicit completion
  markers. Old CLI may omit these fields; explicit non-completed values fail.

Independent reviewer claude_research found missing permitted rate notifications
and unchecked explicit terminal failure markers in20c0fed; corrected in00872d5.
Final read-only review00872d5 reported no blockers.

Verification note: first focused run seed280545 reported39/40 passed,163.1s.
The failed Claude rejection case consumed an edited fixture emitting a permitted
rate event while its VM still used the old parser. That mixed run is not final
acceptance evidence. All implementation/fixture edits were then committed at
00872d5 and frozen for the replacement focused run.
Compile --warnings-as-errors, format --check-formatted and git diff --check
passed on00872d5. Final focused result follows.

Final frozen focused verification:
`rtk proxy asdf exec mix test test/boss/claude_test.exs
 test/boss/delivery_worker_test.exs test/boss/delivery_protocol_test.exs`
passed45 tests, seed286933,191.2s. This includes native finite fixtures for
Claude success (Ready, never Done), reject→Codex fix→fresh Claude review, explicit
Stop with suspended Manager, missing executable before any effect, malformed/
oversized/external-tool/denied/error/missing-report/coverage/duplicate/truncated/
nonzero/refusal/aborted failures, plus existing Codex workflow regressions.
No live model/provider calls. Root owns combined/browser/main verification and
final documentation. Exact next step: merge tested adapter and verify combined UI
and workflow; actual provider acceptance remains opt-in.
