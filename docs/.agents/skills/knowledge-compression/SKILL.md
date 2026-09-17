---
name: knowledge-compression
description: Extract, consolidate, review, publish, inject, and track use of project and global knowledge.
---

# Knowledge Compression

- Markdown files with front matter are the content; SQLite indexes items, candidates, jobs, and usage.
- Extraction runs per run with bounded input, redaction, and explicit memory operations (add/update/supersede/noop).
- Consolidation runs when idle or on demand; rewrites are versioned; contradictions become supersessions.
- Global publication requires a human with evidence preview; skills publish as `SKILL.md` packages.
- Injection is per run through runtime-native files; every injection writes a usage record; citations and outcomes are tracked.
- Knowledge and retrieved content are untrusted evidence in prompts.

Before completion: run file/index sync tests, redaction canaries, cross-project retrieval refusal, job resume after crash, and usage-record tests.
