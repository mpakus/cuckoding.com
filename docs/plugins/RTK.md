# RTK for managed agents and application commands

RTK is optional output optimization, not a permission boundary. The existing
RTK plugin's audited **global** activation is “Use RTK for all agents” in
`/settings/plugins`. Enable that scope once for new managed runs. Project,
board and role restrictions remain narrower; an explicit stage restriction
can only narrow the frozen run policy. Personal CLI configuration is untouched.

## Discovery and snapshots

The bundled integration discovers executable RTK in `/opt/homebrew/bin`,
`/usr/local/bin`, then `/usr/bin`, independently of the native app's restricted
PATH. It checks `--version` against **0.49.0** and fingerprints the executable.
Plugins and agents use this same discovery result. Missing, non-executable,
unsupported or changed binaries visibly fall back without preventing work.
Refresh detection before preparing a new run after replacing RTK; existing
runs keep their recorded binary and activation. No runtime is upgraded.

Run plugin snapshots contain the approved activation, permissions, mode and
per-role overrides. A stage's first `rtk.configuration` event freezes its
resolved configuration for resume. Later global changes affect new runs only;
explicit stage changes cannot expand the run's frozen grant. No new table is
used, and previously prepared runs are not retroactively enabled.

## Agent command boundary and compatibility

All roles receive the same verified executable information, supported-command
guidance and `rtk proxy` escape hatch, including planning, custom delivery roles
and resumed sessions. The app-owned launcher lives at
`<run>/agent/rtk/bin/rtk`; it delegates to the verified installed executable.
Native editing tools remain available. A prompt is not enforcement.

| Pinned adapter | Current agent mode | Gate |
| --- | --- | --- |
| Claude Code 2.1.142 | Instructions only | The required isolated `--bare` mode explicitly skips hooks |
| Cursor Agent 2026.09.15-d2fe57e | Instructions only | Native rewrite permission preservation and isolated hook loading are not verified |
| Codex 0.146.0 | Instructions only | No verified run-owned native hook-trust flow under the current isolated configuration |
| OpenCode / custom adapter stubs | Unavailable | Execution remains unavailable; RTK does not enable an adapter |

**No automatic agent hook is enabled by this release.** A generated hook may
only be connected after the pinned runtime passes rewrite, original-command
permission, configuration-isolation and native trust checks. Do not remove
Claude bare mode, pass Codex's hook-trust bypass flag, trust repository hooks,
or install personal hooks to make a compatibility check appear to pass.
Cursor rejects repository and shared-profile hook configuration. Failed or
unverified compatibility selects the documented instructions fallback.

Use RTK's own `rewrite` engine when testing compatibility; do not create a
second shell parser. The installed 0.49.0 binary returns **3** with rewritten
text when native permission must still be requested, **2** for deny, **1** for
unsupported input and **0** for an allowed rewrite. Its brief CLI help only
mentions 0/1, so that help is insufficient for a safe hook. Already wrapped
commands remain unchanged, and a rewrite never executes the command. Never
turn a failed rewrite or native permission request into an automatic allow.

## Application-owned commands

`CommandPolicy` validates the underlying declaration first. Its synchronous
execution path runs the original absolute executable and argv exactly once,
with the existing working directory, process identity, exit status, timeout,
redaction and artifact. The existing shell-filter adapter then applies
`rtk pipe` to successful, complete, bounded, redacted captured output.
This avoids executable substitution or introducing another shell parser.
The original redacted artifact remains available for diagnosis.

Nonzero exits, incomplete output, streaming `start` calls and explicit
`raw_output: true` calls pass through unchanged. An unavailable filter retains
the captured result; it never reruns the command. Provider JSON streams,
internal machine-readable Git operations and authentication do not pass through
this integration. Commands stored in project policy remain unwrapped.

## State and observations

Run-owned launcher directories are private; changed files and symlinks fail
preparation into the visible fallback. The launcher isolates RTK HOME, disables
raw recall/tee and TOML filters, and never invokes `rtk trust` or `rtk init`.
RTK 0.49.0 ignores its tracking-enabled setting on the command path and
pre-creates a worktree file for SQLite's `:memory:` name. The pinned integration
therefore points its optional tracker at the run-owned `history-disabled`
directory: SQLite cannot open a directory, and RTK continues without persistent
command history. Installed-binary canary checks cover this behavior.

Settings and run views show **Automatic**, **Instructions only**, **Unavailable**
or **Disabled** with a reason as applicable. Automatic currently describes
captured application output filtering, never the agent hook coverage.
`rtk.configuration` and `rtk.command` reuse existing events. Observed provider
tool metadata distinguishes reported RTK invocation, explicit raw-output
exceptions and bypasses. Missing tool detail leaves coverage **unknown**.
An RTK prefix does not prove filtering or reduction. Existing analytics remain
separately labeled **Estimated shell-output tokens avoided**, never billed API
tokens or money saved. No raw command history is imported as trusted policy.

## Verification

```sh
rtk env -u CR_PAT mix test test/cuckoding/plugins test/cuckoding/adapters test/cuckoding/execution/command_policy_test.exs
rtk env -u CR_PAT MIX_ENV=test mix run scripts/rtk_runtime_smoke.exs
rtk env -u CR_PAT mix quality
```

The opt-in smoke uses the installed RTK, a restricted PATH and private temporary
run storage. It checks quoting, compounds, already wrapped and unsupported
commands, exact output, nonzero exit, ignored repository filters and no persisted
canary. Fixture adapter tests cover every role and resume without claiming a
successful real-provider hook. Native delivery evidence belongs in the task
worklog separately from these checks.

References: [RTK 0.49.0](https://github.com/rtk-ai/rtk/tree/v0.49.0)
(Apache-2.0), [Claude hooks](https://code.claude.com/docs/en/hooks),
[Cursor hooks](https://cursor.com/docs/hooks),
[Codex hooks](https://learn.chatgpt.com/docs/hooks). Current documentation is not
proof that a pinned isolated runtime passes these gates.
