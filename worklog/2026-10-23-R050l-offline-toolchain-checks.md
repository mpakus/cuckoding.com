# R050l — Actual offline toolchain checks

Verified locally on `feature/R050l-offline-toolchain-checks`, base `07100fb`.
R050k verified protected worker budgets and watchdog under adverse workloads.
R050l connects those mechanisms to actual toolchain execution and a separate
privileged result channel.

Ponytail full5.3.2 MIT; architecture, runner, security, quality and Swift guidance.
Use RTK proxy for exact source/protocol output. Do not open user projects/profiles
or the unrelated `Untitled.md.age`; no provider usage/publication is authorized.
Keep production stack/grants and the single Start journey unchanged here.

Implemented only the disposable prototype: `guest_toolchain.py` composes pinned
Linux assets and actual synthetic Git commits; `GuestCheckControl` keeps captured
worker bytes separate from privileged control, validates typed scope/hash/size
and waits for native Stopped. Root verifies source types/modes/bytes after group
cleanup; links are refused before privileged hashing. Each cancellation keeps
scope/closure without inventing a test exit. Review moved cancellation intent
before the native stop call to cover delegate/completion ordering.

Pinned inputs: Node `24.22.1-r0`, npm `11.12.1-r0`, Erlang `28.5.0.8-r0` and
official Elixir `1.20.3-otp-28`. Guest startup checks exact observed runtime
versions before each command. The 22-asset manifest totals 76,394,138 bytes;
its SHA-256 is `0ec1d936362a7984a6f285eaddd084339356e49420b32174e93e87a7af4ac39b`.
APK metadata/downloads come from the official Alpine v3.24 aarch64 main/community
repositories. Elixir's
[official release](https://github.com/elixir-lang/elixir/releases/tag/v1.20.3)
provides the OTP28 ZIP; its published digest matched the downloaded bytes.
Alpine's packaged Elixir1.19.6 was not substituted. Package license metadata is
retained; release signature/provenance/licensing/distribution acceptance is open.

Actual verification:

- `rtk proxy python3 -B test/guest_lifetime_probe.py --toolchains` — ten cases
  passed, final fixture `/private/tmp/cuckoding-r050l-_1oy8e9x` and
  `.ccoding/r050l-toolchains-transport.log`. Actual npm exits 0/1 and Mix exits 0/2
  matched passing/failing tests; captured Mix output includes compilation and
  ExUnit results. The failing npm forgery case verifies console and PID1-fd
  access denial, emits a fake passing frame only into captured worker output,
  and remains failed. Replacing source with a device link yields failed despite
  exit0. Output over 62,000 bytes passes through the serialized main-queue decoder;
  output over 64KiB yields no accepted check receipt. Active cancellation
  retains only Cancelled with native Stopped; hard keeper death has no receipt.
- `rtk proxy python3 -B test/guest_check_control_test.py` — nine lifecycle cases,
  each also refusing 21 field mutations. Final fixture
  `/private/tmp/cuckoding-check-decoder-xuor_4tr`. Covers fragments, both result/
  native ordering, no native closure, cancellation taking precedence over a
  completed result, duplicates, invalid UTF8, output/control bounds, foreign
  bindings, wrong JSON types and hash/byte mismatch. No VM is booted by this test.
- `rtk proxy python3 -B test/guest_lifetime_probe.py` — five earlier lifetime
  cases passed, fixture `/private/tmp/cuckoding-r050j-czrn9sh3`; owner loss remains
  explicitly unverified.
- `rtk proxy python3 -B test/guest_lifetime_probe.py --watchdog` — all four
  protected-worker regressions passed, fixture
  `/private/tmp/cuckoding-r050k-_9f3p7x0`. PID/CPU/memory pressure, denied root
  signalling/policy/migration, client EOF and keeper loss retain their boundaries.
- Every run builds with Swift6/MainActor and warnings-as-errors, ad-hoc signs
  only its disposable helper and checks its seal. Argument/mode/canonical-path
  refusals pass before VM creation. Python AST and all three fixed guest shell
  scripts parse; 267 relative documentation links resolve. Production input digest
  remains unchanged, and the existing sealed app passes `codesign --verify --deep
  --strict`. The installed compiler is Apple Swift6.4 (swiftlang-6.4.0.34.1).

Final toolchain proof hashes:

| Artifact | SHA-256 |
| --- | --- |
| Kernel | `256d5fff4bb892edcb9218c1e6353e388bc3646e65f76c2bc9d958b635d1b00e` |
| Compressed ramdisk | `06fc9553834689a0bd0e2e58139b7fb80e5ab65c2396573b1eb2ffc6008a126f` |
| Native main source | `730037c62573b30078e03256e344cc4d3ed5939995b882be9d74a38fb22106df` |
| Control decoder | `39882ff137085d3e22707fae6ae8b9a9a661316850a69c1df8d0bbc6a10b0bdc` |
| Signed disposable helper | `32424c9e7f295e19134de8ceb2638505a91b5fce42fd43d6f964c2b082c70584` |

The retained `toolchain_sha256` separately fingerprints the pinned manifest and
guest policy scripts. It is not the ramdisk/kernel hash or a production image
attestation. The guest has two CPUs/1GiB, no attached network/storage/socket/share
devices; the worker group has 128 PIDs, 512MiB, no swap and one CPU. BEAM JIT needs
memory-backed files, so per-file size is bounded at 64MiB while captured output
has its separate 64KiB acceptance ceiling and the whole guest has a finite deadline.

Retained investigation failures:

- `5l23senx` refused a known BusyBox shell-link collision during image assembly;
  preserve the validated base shell link explicitly.
- `5yjjq6we` completed actual npm but the observer rejected an unstructured
  diagnostic. Host events now use the existing JSON line protocol.
- `01h6vtjp` exposed omitted intermediate directories in the Elixir ZIP. Add
  validated parent directories before composing initramfs; never extract host links.
- `4tiuscx6` reached Mix but returned SIGXFSZ/153 with the initial tiny file
  limit. Raising only the disposable artifact limit while separately bounding
  output allowed actual ExUnit to run.
- `4vz_pxxr` and `725ugqiq` passed earlier eight/nine-case iterations.
  `eugvf7m3` also passed nine cases including cancellation ordering. Final transport
  evidence adds serialized control fragments and a near-limit actual output. Every
  retry used a fresh root; failed receipts were not rewritten.

Temporary-space maintenance removed only exact completed fixtures' regenerable
SDK module caches, checking all non-cache files before/after. Identical pinned
archives and matching kernel/ramdisk bytes were APFS-cloned to share blocks, verifying
paths/bytes remained unchanged. Two prelaunch disk-guard refusals created no
fixture or VM; the guard remains at 2GiB. All fixture source/image/binary/log/receipt
artifacts remain. The unrelated encrypted file stays unread/unmodified/untracked;
no real workspace, profile or inference was used.

Scope and handoff: production grant `codex-check-single-process-v1` is unchanged
and cannot accept `guest-check-prototype-v1`. No application rebuild, full app
suite, real-project dependency pipeline, live provider, physical sleep, Developer
ID/notarization or release acceptance is claimed by this slice. Next implement
production image/candidate transport, immutable permission/receipt integration,
supervised OTP ownership and keeper-loss recovery before exposing toolchains in
Start. Current app build/source digest remains unchanged. Claude subscription
integration still requires Anthropic approval, which has not been established.
