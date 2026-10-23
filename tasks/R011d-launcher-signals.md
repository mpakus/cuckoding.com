# R011d — Lock-free source-launcher shutdown signals

Status: implemented and verified, 2026-10-23; local integration pending.

- [x] Reproduce the signal/Event critical-section shutdown deadlock in isolated
  launcher fixtures, without a provider, real app data or unowned processes.
- [x] Keep signal handlers free of locks; repeated SIGINT/SIGTERM must close
  admission to heartbeat/startup and reach the existing backend cleanup once.
- [x] Verify simulated critical-section/startup signals and real source launch/
  graceful stop, retained data, listener and lock cleanup. No forceful shutdown
  is a passing graceful-stop result.
- [ ] Update docs/AGENTS/README and merge locally to main; delete feature branch.

This changes only the developer launcher, not native/provider cleanup authority.
Evidence: [worklog](../worklog/2026-10-23-R011d-launcher-signals.md).
