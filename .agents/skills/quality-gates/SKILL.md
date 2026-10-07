---
name: quality-gates
description: Define or run verification and release evidence.
---

# Quality Gates

- Run the relevant subset from `AGENTS.md` testing gates and record exact commands and results in the worklog.
- Never check an acceptance item without evidence tied to the artifact under test.
- Release evidence includes clean-machine install, sleep drill, update/rollback, provider degradation and conformance for any implemented plugin kind.
- During the documentation reset, application checks are unavailable until their sources exist; use `docs/TESTING.md` and never reuse historical passing counts.
