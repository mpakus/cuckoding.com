# R050j — Test an isolated guest lifetime boundary

Status: completed prototype, 2026-10-23. Base `a709494`; local integration only.

- [x] Verify the installed Apple Virtualization API and official guest input
  provenance; retain hashes/licenses. Use a fresh private disposable root only.
- [x] Prototype a bounded Linux guest with no network, host share, provider,
  account or project access. Keep host probes trusted and fixed. Limit CPU,
  memory, output, guest workload and total lifetime; retain failures.
- [x] Observe guest child/group/session escape, then native forced VM stop and
  final Stopped state. Test cancellation/deadline/owner-loss where supported;
  distinguish observations from actual cleanup authority and remaining gaps.
- [x] Leave a repeatable focused regression or an exact reproducible negative
  result; update docs/AGENTS/README and merge local main without publication.
  Do not enable toolchain checks or alter the shipping NPROC/provider grants.

This is a prerequisite to the full Mix/npm check implementation, not a narrower
replacement for it. Packaging/toolchain/worktree/evidence integration and actual
acceptance remain required after a proven boundary.

The five-case final probe passed native stop observation on input/EOF/deadline/
paused stop, and retained owner loss as unverified. This does not establish the
missing owner-loss boundary or enable toolchains. [Evidence](../worklog/2026-10-23-R050j-guest-lifetime-prototype.md).
