---
name: cuckoding-architecture
description: Change component boundaries, state ownership, or extension contracts.
---

# Architecture Guardrails

- SQLite is authoritative; processes cache or execute only.
- Behaviours at every replaceable boundary: runner, adapter, plugin kinds, knowledge backend, VCS host, secret store, metric collector.
- The shell is replaceable through the shell contract; Phoenix owns everything else.
- Host runner limitations are stated, never hidden; runner plugins declare isolation claims.
- Record any boundary change as an ADR before implementation.
