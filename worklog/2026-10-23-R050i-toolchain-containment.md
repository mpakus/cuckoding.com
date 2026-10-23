# R050i — Toolchain containment prerequisite

Investigation verified and merged locally. Branch
`feature/R050i-toolchain-containment`, base `7b1b699`.
Ponytail full 5.3.2 MIT; local-runner, security, architecture and quality guidance.
Exact-output `rtk proxy` preserves source/probe semantics. No shipping grant,
runtime account, user workspace or unrelated encrypted file access.

The existing single-process checks prevent fork with hard RLIMIT_NPROC=0.
Before permitting Mix/npm descendants, verify whether native macOS sandbox rules
can prevent a child leaving its owned process group/session. The previous
session-leader setsid denial is not that proof. Use trusted self-authored probes
that immediately report and exit, with parents waiting for every child.

## Source and observed result

Apple XNU revision `f6217f891ac0bb64f3d375211650a4c1ff8ca1ea` (APSL 2.0 /
per-file BSD notices), inspected without incorporating upstream source:

- [bsd/kern/kern_prot.c:484–529](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_prot.c#L484-L529)
  implements `setsid_internal`/`setsid`; `setpgid` is at 571–638. Neither path
  invokes an extensible MAC session/group authorization hook in this source.
- [security/mac_policy.h](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/security/mac_policy.h)
  contains no setsid/setpgid hook names.
- [bsd/sys/event.h:364](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/sys/event.h#L364)
  marks NOTE_TRACK/NOTE_CHILD/NOTE_TRACKERR unsupported since 10.5.

The running kernel reports **Darwin 27.0.0**. The pinned public source is supporting
reasoning, not a claim that its revision exactly matches the installed kernel.
The actual local probe supplies the observed result below.

Private evidence root: `/private/tmp/cuckoding-r050i-70b_wzxb` (0700). A
self-authored, warning-clean C probe uses only one child at a time. Each child has
a three-second alarm, immediately reports the result and exits. Its parent has
a ten-second alarm and `waitpid`s all three children. Python starts an owned
session and caps each invocation at fifteen seconds. No background workload,
unknown PID signalling, project path, account, provider or network access.

Compiled with `/usr/bin/clang -Wall -Wextra -Werror -O1 probe.c -o probe` and run
once directly and once through `/usr/bin/sandbox-exec -f probe.sb`. Every command
was orchestrated under `rtk proxy python3`; the unsandboxed run is a positive
control. The research-only profile is deny-default with process-exec/process-fork,
file reads for loading the trusted probe, sysctl-read and mach-lookup allowed.
It is never an application/provider grant. Only a fresh private canary path is
attempted for writing.

| Probe | Unsandboxed | Deny-default Seatbelt |
| --- | --- | --- |
| Fresh write canary | allowed | refused, EPERM |
| Nonleader child `setsid` | success, group changed | success, group changed |
| Nonleader child `setpgid(0,0)` | success, group changed | success, group changed |
| `posix_spawn` with SETPGROUP | new group | new group |
| Parent waiting/reaping | all three, exit zero | all three, exit zero |

Hashes (SHA-256): probe source
`e7f45611b82d529ff1b248ec6f84ed696e2448b5155301e3cd8414d06688705a`;
binary `67ceffc0548ebfa35ccd7a20bb1c3cc3094d1f4b2c9ab49e299524134a066aeb`;
profile `a73879ea4d192dd31bff40c7a17933f97da989bc6eb6e0281b98f24ac79b2eb0`.
Raw public results are retained as `unsandboxed.json` / `seatbelt.json` beside
the probe and pinned source copies. The Python.org trust store initially refused
the source HTTPS certificate; system curl with verification enabled succeeded.
No TLS bypass or host trust-store change.

## Decision and remaining implementation

Reject the proposed shortcut of permitting fork while relying on the original
process group. The current hard NPROC=0 remains. The existing setsid denial from
a session leader did not establish child containment. No production source,
grant, dependency, data schema or native artifact changes in this research slice.

A new subprocess grant needs a prototype with an OS-enforced descendant lifetime
boundary. It must prove fork/double-fork/spawn/exec, group/session escape,
supervisor death, cancellation, deadlines and complete cleanup without PID polling
or lost-parent inference. It also needs explicit toolchain/dependency read grants,
workspace isolation, output bounds, durable receipts and independent review.
An isolated guest is one candidate; it has not been selected or installed. Merely
adding a privileged monitor or wrapping commands does not supply this proof.

Verified **219** local Markdown targets, retained probe status/expected results,
source hash and whitespace. Recomputed application input digest still matches
R020s's sealed artifact exactly. Reviewed the negative result against the existing
single-process contract; no claim that every conceivable macOS boundary is
impossible. Commit `6302a60` fast-forwarded into local main; feature branch deleted.
No full suite/build rerun is required for this docs-only slice; R020s's sealed
artifact and verified application source remain unchanged. General toolchains,
real-provider, recovery/physical sleep and release acceptance remain open.
