# 0803 — Reference Plugins: RTK, Ponytail, XERJ, Generic MCP Server

## Objective

Implement the four reference plugins per `docs/plugins/` and `docs/PLUGINS.md`, with detection, permissions, contributions labeled in run detail, and clean degradation when the binary is absent.

```yaml
status: done
owner: codex
started_at: 2026-09-18
worklog: worklog/2026-09-18-0803-reference-plugins.md
```

## Dependencies

- 0802.

## Scope

Implement the four reference plugins per `docs/plugins/` and `docs/PLUGINS.md`, with detection, permissions, contributions labeled in run detail, and clean degradation when the binary is absent.

## Deliverables

- Four plugins with manifests and tests.

## Checklist

- [x] RTK validates the underlying command; analytics labeled as estimates.
- [x] Ponytail scoped per stage; policy overlay enforced.
- [x] XERJ behind the `KnowledgeBackend` behaviour; namespaces server-derived.
- [x] MCP server implementation is maintained and exactly pinned with integrity evidence; permissions are declared and tools allowlisted.

## Acceptance criteria

- [x] E2E scenario 9 passes.

## Verification and evidence

Focused fake-binary and run-detail suite: 11 tests, 0 failures. Read-only
installed-tool discovery: all four prerequisites available, no manifest errors.
