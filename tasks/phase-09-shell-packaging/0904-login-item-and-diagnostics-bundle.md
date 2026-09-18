# 0904 — Login Item and Diagnostics Bundle

## Objective

Add the login-item toggle, About panel, and the redacted diagnostics bundle including plugin states and power events.

```yaml
status: complete
owner: codex
started_at: 2026-09-18
worklog: worklog/2026-09-18-0904-login-item-diagnostics.md
```

## Dependencies

- 0901.

## Scope

Add the login-item toggle, About panel, and the redacted diagnostics bundle including plugin states and power events.

## Deliverables

- Settings and bundle generator.

## Checklist

- [x] Bundle excludes source, prompts, credentials, full env.

## Acceptance criteria

- [x] Bundle passes canary tests.

## Verification and evidence

The focused tests and packaged-app verifier generated and inspected bundles in
normal and safe mode. They confirmed the fixed seven-file allowlist, owner-only
permissions, launch-token exclusion, and rejection of sensitive fixture fields.
Exact commands and results are recorded in
`worklog/2026-09-18-0904-login-item-diagnostics.md`.
