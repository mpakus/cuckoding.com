# RTK Plugin (`shell_filter`)

## Role

RTK reduces noisy shell-command output before it enters an agent context. It is an optimization layer, not a security boundary and not a required product dependency.

Repository contributors and agents nevertheless use RTK for every shell command in this repository. These are separate concerns: the contributor convention reduces working-context noise now, while the product plugin remains optional so Cuckoding still works when RTK is absent.

## Manifest highlights

- `kind: shell_filter`; detect a pinned `rtk` binary and version.
- Permissions: `host_process: true`, `read_paths: ["${RUN_WORKTREE}"]`.
- Capabilities: `shell_filter.wrap_command`, `shell_filter.analytics`.

## Behaviour mapping

- `wrap/3`: given a declared command and the runtime's hook conventions, return the wrapped invocation or `:passthrough`. Policy validation runs on the underlying command, never on the wrapper. Exit code, duration, and enough diagnostics to debug failures are preserved.
- `analytics/2`: import machine-readable gain data (for example `rtk gain --all --format json`) and attribute to run/session where possible; store raw and compact bytes, estimated tokens, filter version, and estimation method.

## Safety rules

- Never let compaction hide a test failure or change command semantics.
- Exclude commands whose streaming output is operationally required unless verified.
- Runtime-native read/search tools bypass shell hooks; report coverage ratio.
- Use `rtk proxy <command> ...` only when exact unfiltered streaming output is operationally required or an adapter changes semantics; record the exception in the worklog.
- Store and validate the underlying command in project configuration. Apply the wrapper only after command-policy validation so `rtk` cannot obscure what is authorized.

## Dashboard language

"Estimated shell-output tokens avoided" and "RTK output reduction". Never "API tokens saved" or "money saved".
