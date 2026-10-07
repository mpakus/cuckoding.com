---
name: agent-adapter
description: Add or change a coding-agent runtime integration on the host runner.
---

# Agent Adapter

- Implement the operations in `docs/AGENT_RUNTIME_ADAPTERS.md`; record supported capabilities and the effective runtime permission grant.
- Separate executable discovery, version compatibility, authorization and model discovery; cache only validated non-secret model metadata.
- Map the capability grant onto the runtime's own permission system; report unenforceable restrictions as `unenforced`.
- Keep requested and actual model separate; usage carries source and confidence.
- Generate instruction, skill, and MCP files only in the run's `agent/` folder; never touch the user's global runtime config or memory.
- Handle sleep gaps: probe process identity and session before deciding to resume or recover.

Before completion: run conformance checks for malformed output, cancellation, sleep-gap recovery, secret canaries and evidence provenance; record real-provider authorization/model tests separately.
