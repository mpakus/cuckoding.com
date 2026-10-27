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
