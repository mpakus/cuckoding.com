# R050j — Isolated guest lifetime prototype

Completed prototype on `feature/R050j-guest-lifetime-prototype`, base `a709494`;
local integration only. The full toolchain/recovery acceptance remains open.
Previous goal turn made progress: R100d actual packaged restart/refusal and
lifecycle verification merged. Full toolchain checks remain unavailable because
R050i proved macOS process-group escape. Test the next implementable boundary.

Ponytail full 5.3.2 MIT; architecture, runner, security, quality and Swift guidance.
Swift is only a disposable SDK prototype here; the Elixir/OTP/Rust application
stack and shipping grants are unchanged. Prefix all commands with RTK, using
proxy for exact source/protocol output. Preserve `Untitled.md.age` unread/unstaged.

Installed Darwin27.0.1, arm64, Xcode SDK and Virtualization headers are current
local evidence. Initial free temporary-volume space is 5.7GiB; keep downloaded
inputs bounded and do not remove unrelated files to gain space. No real provider,
saved workspace/profile, network inside the guest, or host directory share.

## Sources, resources and provenance

Apple's installed SDK `Virtualization.framework/Headers/VZVirtualMachine.h`
defines the serial queue requirement, explicit Running/Paused/Stopped states,
required virtualization entitlement and forced-stop completion/error contract.
The [official Linux sample](https://developer.apple.com/documentation/virtualization/running-linux-in-a-virtual-machine)
and [stop API](https://developer.apple.com/documentation/virtualization/vzvirtualmachine/stop(completionhandler:))
were read, including Markdown retained privately when the web reader refused its
content type. Use standard API shapes; no upstream implementation is incorporated.
The disposable helper uses the main actor/queue throughout native state changes.
Installed Swift is **6.4** (`swiftlang-6.4.0.34.1`), verified locally; strict Swift6
compilation succeeds without warnings. No production Swift target is introduced.

[Alpine's official downloads](https://alpinelinux.org/downloads/) supplied pinned
3.24.3 aarch64 inputs; system curl uses verified HTTPS with inherited curl config
disabled and a cleared private environment. The first download checked publisher
SHA files; the repeatable probe pins those exact hashes and refuses drift:

- `alpine-virt-3.24.3-aarch64.iso`: 93,452,288 bytes,
  `e34603080e942e9ebc670689eee77dd7a6551c823a6ff5a299e308ded268098f`.
- `alpine-minirootfs-3.24.3-aarch64.tar.gz`: 4,029,999 bytes,
  `4d3f80afaebd447c5591a63a73bde380a149fe8b2d85488cafabb2ff97551f50`.

Only the fixed kernel member is read from the ISO, and two regular bounded
BusyBox/musl members from the root archive are selected into memory. No host
archive links/devices are extracted. The kernel's EFI zboot wrapper contains
gzip, rather than a raw ARM image. Its bounded offset/size parse follows
[Linux6.18 zboot-header.S](https://github.com/torvalds/linux/blob/7d0a66e4bb9081d75c82ec4957c50034cb0ea449/drivers/firmware/efi/libstub/zboot-header.S),
checked at the resolved v6.18 commit. This is format evidence, not a claim that
the reference revision exactly matches Alpine's 6.18.58-0-virt kernel.
The extracted image is 36,306,944 bytes and has the ARM64 header. The observed
kernel config has built-in virtio console/PCI support. The minimal self-authored
RAM filesystem follows the [kernel's newc format](https://docs.kernel.org/driver-api/early-userspace/buffer-format.html).

Package metadata reports BusyBox1.37.0-r31 GPL-2.0-only and musl1.2.6-r3 MIT;
the kernel reference has GPL-2.0 source notices. Binaries, headers, SDK caches and
images remain private downloaded test inputs, not committed/shipped dependencies.
Redistribution, provenance and installer/license acceptance are still required.
Final free temporary-volume space was 4.66GiB; no unrelated files were deleted.

## Actual prototype and results

`test/guest_lifetime_probe.py` accepts no existing data root or arbitrary command.
It creates a fresh private root, checks architecture/free space, bounds downloads,
validates fixed hashes, builds the RAM filesystem and compiles/ad-hoc signs only
`test/support/guest_lifetime_probe.swift`. Its private research entitlement is not
added to Cuckoding. The guest has two virtual CPUs, 512MiB, one serial console
and no storage/network/socket/directory-share devices. There is no provider,
project, shared candidate, account or credential. This is a trusted prerequisite
probe, not an untrusted-workload runner.

Finite BusyBox children start in separate guest sessions/groups, including an
exec/double-fork child reparented to guest PID1. Each child emits at most thirty
ticks; the trusted PID1's watchdog powers off after forty guest seconds. It is
not yet a privileged watchdog policy protected against an untrusted workload.
The native helper owns a ten-second deadline case/twenty-second fallback; the
parent bounds output, waits/reaps its exact owned child, and retains failures.
No unrelated process/group is signalled. Native stop completion with no error
and explicit Stopped state must precede an observation file; guest text and
process absence cannot establish that observation.

Final `rtk proxy python3 test/guest_lifetime_probe.py` passed all five cases at
`/private/tmp/cuckoding-r050j-ch_1lyeh`:

| Case | Observed result |
| --- | --- |
| Controller input | Native Stopped, 1.207s, exact controller_input reason |
| Controller EOF | Native Stopped, 1.197s, exact controller_eof reason |
| Deadline | Native Stopped, 10.612s, exact deadline reason |
| Pause then stop | Native Paused then Stopped, 1.202s |
| Owned helper SIGTERM | No stop receipt, 1.202s stream/process observation; **cleanup unverified** |

The last case intentionally never claims that the guest is cleaned up, even
though the stream closes and the owned helper is reaped. No shipping recovery
or admission may derive authority from that observation. Normal four-case stop
observations likewise remain research metadata, not current battle receipts.
All probe leaders were waited/reaped; no owned probe executable remains. This
does not independently prove guest cleanup after the owner-loss case.

Private `.ccoding/r050j-probe-final.log`, per-mode logs/observations and
`evidence.json` retain the exact results. Final hashes:

- Kernel `256d5fff4bb892edcb9218c1e6353e388bc3646e65f76c2bc9d958b635d1b00e`.
- RAM filesystem `8a94abf4d1e5d21afddccb6b31b7d6fc10df7bae3b6b52cb7c0971ce5413fceb`.
- Swift source `e22fdff5fab87f74ce0f632ddad36e1cefafa610637ee0a16f8f4054f9d58e72`.
- Probe binary `25ef141ab6f739a27ff76cbb46f879b8c478b12213bf152445a55c9be23cc03a`.

## Verification, corrections and limits

- Strict Swift6/default-main-actor/warnings-as-errors compile and strict signature
  verification passed. Fixed missing/unknown-mode and noncanonical-path refusals
  execute before VM creation.
- Address Sanitizer compilation and canonical-path refusal passed without any
  diagnostics; `.ccoding/r050j-asan.log`, private binary in the retained failed
  fixture root. POSIX realpath ownership stays inside one small function.
- A private-copy mutation inverts the explicit Stopped-state gate. The real input
  case fails and no stop receipt is written, as required. Fixture
  `/private/tmp/cuckoding-r050j-xsbjv39u`; shipping/probe source is unchanged.
- Initial raw-kernel assertion caught EFI wrapping before any VM started. Initial
  Foundation standardized URLs collapsed `/private/tmp` to `/tmp`; direct URL plus
  POSIX realpath preserves canonical scope. The first complete harness required
  LF-only ticks and failed on console CRLF; it safely hit the native fallback
  stop. The harness now accepts only CR/LF line endings, retaining raw logs.
  Earlier roots `/private/tmp/cuckoding-r050j-fn0t5mha` and
  `/private/tmp/cuckoding-r050j-8fbkm5nk` remain untouched as development evidence.
- Python AST/syntax, local documentation references, whitespace and current
  application input-digest equality passed. No full Elixir/Rust/build rerun was
  needed for this opt-in test/docs slice; application inputs exactly match the
  previously sealed R100d artifact. No historical count is presented as a new run.

Next implementation needs a protected untrusted-worker watchdog and owner-loss
closure/reconciliation, exact private candidate/toolchain transport, finite
toolchain image/read/dependency grants, bound receipts, supervised OTP admission
and settlement, actual Mix/npm checks, packaging/licensing and physical/real
acceptance. The existing single-process NPROC=0 remains. No new runtime, app
entitlement, schema, provider usage, user data access, push or publication.
The complete beta goal remains active; this prototype is not beta completion.
