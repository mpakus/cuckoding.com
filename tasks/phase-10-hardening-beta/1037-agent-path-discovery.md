---
status: done
owner: codex
started_at: 2026-09-24
worklog: worklog/2026-09-24-1037-agent-path-discovery.md
---

# 1037 — Find installed agent executables

- [x] Autofill a verified executable from PATH, standard CLI directories or Codex Desktop bundles.
- [x] Support the native shell's restricted environment without granting agent access to the personal home.
- [x] Keep manual editing and provide an explicit rescan with truthful found/not-found feedback.
- [x] Preserve saved authorization locks, runtime compatibility checks and app-owned sign-in.
- [x] Cover discovery, manual override and setup behavior with focused tests and rendered verification.
- [x] Reconcile the recent design, illustration modes, executable discovery and testing descriptions in `docs/` and `AGENTS.md`, preserving implementation changes and distinguishing source, integration, packaging and release evidence.
- [x] Record the clarified Speculator/Implementor/Reviewer contract, return-to-Speculator comment loop and extensible roles/permissions, with current implementation gaps explicitly left open.
