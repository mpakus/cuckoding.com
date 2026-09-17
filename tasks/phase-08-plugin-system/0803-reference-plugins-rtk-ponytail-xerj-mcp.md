# 0803 — Reference Plugins: RTK, Ponytail, XERJ, Generic MCP Server

## Objective

Implement the four reference plugins per `docs/plugins/` and `docs/PLUGINS.md`, with detection, permissions, contributions labeled in run detail, and clean degradation when the binary is absent..

## Dependencies

- 0802.

## Scope

Implement the four reference plugins per `docs/plugins/` and `docs/PLUGINS.md`, with detection, permissions, contributions labeled in run detail, and clean degradation when the binary is absent.

## Deliverables

- Four plugins with manifests and tests.

## Checklist

- [ ] RTK validates the underlying command; analytics labeled as estimates.
- [ ] Ponytail scoped per stage; policy overlay enforced.
- [ ] XERJ behind the `KnowledgeBackend` behaviour; namespaces server-derived.
- [ ] MCP server implementation is maintained and exactly pinned with integrity evidence; permissions are declared and tools allowlisted.

## Acceptance criteria

- [ ] E2E scenario 9 passes.

## Verification and evidence

Run plugin tests with fake binaries and opt-in real binaries.
