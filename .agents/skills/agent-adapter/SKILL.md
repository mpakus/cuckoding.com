---
name: agent-adapter
description: Add or change a coding-agent runtime integration on the host runner.
---

# Agent Adapter

- Implement every `AgentAdapter` callback including `render_config/2`; record the effective runtime permission grant.
- Map the capability grant onto the runtime's own permission system; report unenforceable restrictions as `unenforced`.
- Keep requested and actual model separate; usage carries source and confidence.
- Generate instruction, skill, and MCP files only in the run's `agent/` folder; never touch the user's global runtime config or memory.
- Handle sleep gaps: probe process identity and session before deciding to resume or recover.

Before completion: pass the conformance suite including malformed output, cancellation, sleep-gap recovery, secret canary, and knowledge citation tests.
