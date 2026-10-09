# Runtime adapters

Status: R020a–d implement Codex version readiness, private-profile status,
validated catalog caching, managed ChatGPT login/logout, a fixed model diagnostic
and R040e/f brief/document-snapshot planning. Codex `0.146.0` and
`0.162.0-alpha.2` are explicit version baselines; other versions remain unverified. Human-completed login,
signed-in real-model acceptance and repository turns remain open. Claude Code, Codex,
Cursor and Hermes are requested targets;
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
| Codex | 0.146.0 version, signed-out status, login start/cancel and restrictive thread preflight; 0.162.0-alpha.2 private-account/catalog refresh and effective-config preflight; successful model diagnostic uses fixtures | Human-completed login, real responses, repository grants/turns and cancellation |
| Claude Code | Pending | Current official interface, safe reusable authorization, models/default behavior and permission boundary |
| Cursor | Pending | Current official CLI identity, profile/history behavior, model discovery and project config isolation |
| Hermes | Pending | Confirm intended runtime/distribution, supported headless interface, authorization, model catalog and enforceable grants |
| Additional runtime | Deferred until requested | Same conformance contract; a saved name/path alone does not enable execution |

Do not copy legacy CLI flags or assert identical provider capabilities. Record
the verified version and official source date in the implementation worklog.
If Hermes refers to a different distribution than the adapter implementor finds,
resolve that identity before installing/launching it. This planning reset installs
no providers or plugins.

The version adapter callback is `probe/3`. Its native helper runs only
`--version`, with a five-second deadline, 128-byte provider-output ceiling and
1 KiB host response ceiling. HOME, CODEX_HOME, TMPDIR and working directory point
to a new private app scratch directory; stderr is discarded and only validated
version/status/timing/ownership observations reach SQLite. The helper clears
inherited environment and stops the whole owned group before reaping its leader,
including on cancellation, stdin loss and timeout. No account files are read or
copied by Cuckoding. Scratch files are retained under `probes/`; this is host
execution, not filesystem confinement. Select only trusted executables. A forced
kill of the helper itself still needs later ownership reconciliation; persisted
PIDs are never used to kill a process, and interrupted work is not auto-replayed.

R020b adds `inspect_connection/3`: initialize → effective config check → account/read
→ model/list only for a reported managed ChatGPT account. The helper forces file
credential storage and the OpenAI provider; rejects an unexpected profile,
unsupported effective config, linked/special profile files, server requests and
account changes after the authoritative account snapshot. R020g permits an
`account/updated` notification only while waiting for `account/read`, as observed
on 0.162.0-alpha.2; unsolicited login completion and server requests still fail.
Profile inspection is metadata-only and capped
at 32,768 entries (the observed bundled-plugin cache alone exceeded 7,000). This is host-process hygiene, not a sandbox or an MDM bypass.

Stdio has 64 KiB frame / 512 KiB cumulative limits, bounded channel buffering,
a ten-second deadline and the same owned-group cleanup. Model discovery accepts
at most four pages of 32 entries with `includeHidden:true` on every request.
R020f includes entries hidden from the agent’s default picker, validates/stores
the boolean `hidden` flag, and exposes them as additional models in Agents/Team.
Older normalized rows without the flag remain readable. Repeated cursors/IDs, invalid metadata or a
partial failure cannot publish a partial catalog. A catalog failure does not
rewrite a successful account observation. Emails, plans, raw errors and unknown
fields are discarded. The host validates normalized output again before SQLite.
Only IDs, labels, visibility and default/effort/input metadata survive. Catalog provenance is
`codex-app-server/model/list`; this may be runtime-cached metadata, not entitlement.

R020c adds `authorize/5` for fixed login/logout operations. Login sends
`account/login/start` with `type=chatgpt`, validates an official HTTPS authorization
URL, waits for the matching `account/login/completed`, then refreshes account/models.
Cancellation attempts `account/login/cancel` before owned-group termination. Logout
uses `account/logout` and requires a subsequent signed-out observation. Each RPC
is limited to ten seconds; login has a ten-minute monotonic/wall-clock deadline.
All profile helpers hold an exclusive native lock through group cleanup.
These account operations cannot launch a turn.

R020d adds `check_model/6`, a single fixed diagnostic rather than a general RPC
interface. It checks the current private account/catalog, starts an ephemeral
thread and verifies model/provider, permissions, instruction sources and scratch
scope before a fixed prompt. Codex 0.146.0's experimental named permission profile
denies root access and grants read access only to the empty scratch path, with
command network disabled. Effective config also disables shell/edit/browser/MCP,
plugins, hooks, memory, multi-agent and permission-expansion paths. No provider
model fallback is allowed. Unsupported config or a wider returned grant aborts.

The native helper requires matching thread/turn IDs, completed status and exactly
`CC_READY`; tool activity, rerouting and foreign completion fail. Bounded queued
notifications cover completion arriving before the turn/start response. Raw text
and hidden reasoning are discarded. Requested and runtime-selected models are
stored separately; this is the runtime's report, not independent proof of backend
model identity. Deadline is 120 seconds (monotonic and wall), with ten-second RPC
limits, turn/interrupt on cancellation/failure, then owned-group cleanup. Cuckoding
stores only a closed 1 KiB public receipt. Provider usage may precede cancellation.

Real acceptance so far: installed Codex initialized a fresh profile, returned
not_connected, and started/cancelled browser login without an auth file. R020f also verified a read-only full catalog fetch from the existing signed-in
private profile: six entries, three hidden from the default picker. The returned
set depends on the installed client and account. R020g observed ten entries from
desktop 0.162.0-alpha.2 with the same private sign-in, including GPT-6.1 Sol and
GPT-6 Astra/Sol/Luna; Terra is advertised as GPT-5.6 Terra. The selected standalone
0.146.0 returned six even with hidden models included. The UI offers an explicit
desktop path choice followed by the ordinary consented version/connection checks;
no selected runtime or saved model binding is silently replaced. No model IDs are
invented or borrowed from another client. Login completion itself was not driven
by that check. Human-completed login acceptance, revoked
access, concurrent session reuse, physical sleep recovery and real scoped turns
remain R020 gates. A fresh-profile real thread preflight verified the restrictive
response without calling turn/start; a signed-out model check refused inference.
These are not real model-response or adversarial filesystem-grant acceptance.
No API key is requested.

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

R040e adds `plan/5` to the adapter, reusing the restricted diagnostic transport.
`--plan-codex-brief` accepts one bounded JSON line on stdin followed by the existing
cancel/EOF signal. It adds a fixed per-turn `outputSchema`, accepts only matching
public assistant completion and returns a bound proposal receipt. Elixir validates
the closed proposal schema again before storage. This does not expose arbitrary
prompts with tools, general RPC, repository reads/writes or custom execution roles.

R040h freezes `brief-plan-v2` in new requests and forwards it through the existing
stdin boundary. Its outputSchema requires `depends_on` and `sources` integer
arrays in addition to task text. The fixed reference instructions require earlier
task indices and selected-document indices; Elixir validates ordering and request
scope before persistence. Saved v1 requests use the original schema and receipts
remain unchanged. Runtime permissions, model matching and cancellation are unchanged;
v2 successful responses currently have fixture evidence only.
