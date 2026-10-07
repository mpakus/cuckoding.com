# Runtime adapters

Status: requirements, not a current support claim. The prior source and version
pins were removed. Claude Code, Codex, Cursor and Hermes are requested targets;
each needs current official documentation and real installed-version evidence.

## One replaceable boundary

An adapter must support or explicitly report unsupported:

| Operation | Required normalized result |
| --- | --- |
| Discover / version | Executable metadata, version and compatibility reason |
| Authorize / status / disconnect | Non-secret status under the selected app-owned profile |
| Models | Bounded account-scoped catalog, capabilities, source/freshness or unsupported |
| Launch | Role/spec/candidate context, selected model, effective grant and session/process identity |
| Activity | Public text/tool summaries, artifacts, usage when reported, terminal outcome |
| Cancel / inspect / continue | Verified lifecycle and resume capability; fresh-session fallback |

Requests contain Arena, Tabula, battle, task, attempt and role IDs; immutable
workflow/policy revisions; approved worktree and input artifacts; model; limits;
allowed checks; output contract and stable command key. Never pass an entire
environment or credential value.

Responses are untrusted. Parse bounded structured messages; discard hidden
reasoning and raw secret-bearing arguments. A process exit or natural-language
“done” is not a Secutor pass. Preserve malformed/failed outcomes as safe error
codes and redacted diagnostics. Protocol output is separate from logs and never
goes through RTK filtering.

Use the smallest supported provider interface that preserves this contract.
A structured CLI/API is acceptable. ACP may unify capable runtimes, but no
mandatory bridge framework, terminal scraping or invented capability is needed.
Pin and verify any bridge binary, source license and build provenance when one
is actually required.

## Provider evidence checklist

| Target | Rebuild status | Evidence needed before enabling execution |
| --- | --- | --- |
| Codex | Pending | Current official interface, app-owned login, isolated launch/model listing, grant mapping and cancellation |
| Claude Code | Pending | Current official interface, safe reusable authorization, models/default behavior and permission boundary |
| Cursor | Pending | Current official CLI identity, profile/history behavior, model discovery and project config isolation |
| Hermes | Pending | Confirm intended runtime/distribution, supported headless interface, authorization, model catalog and enforceable grants |
| Additional runtime | Deferred until requested | Same conformance contract; a saved name/path alone does not enable execution |

Do not copy legacy CLI flags or assert identical provider capabilities. Record
the verified version and official source date in the implementation worklog.
If Hermes refers to a different distribution than the adapter implementor finds,
resolve that identity before installing/launching it. This planning reset installs
no providers or plugins.

## Conformance

One shared test contract covers parsing, split output, unknown events, malformed
frames, bounded memory/logs, secret canaries, requested/actual model separation,
permission refusal, cancellation/descendants, lost transport ownership, crash,
sleep gaps, expired authorization and concurrent sessions. Real-provider tests
then establish login reuse and actual grants/global writes; fakes cover only
the host contract.

Session continuation requires compatible account, model, runtime, role,
workspace, policy and spec identity. Otherwise use a fresh session with public
evidence. Never reuse an Implementor conversation as Secutor's independent
review or share writable session state between clones.
