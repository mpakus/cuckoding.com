# Packaged ACP bridges

Build dependencies are pinned by `package-lock.json`; installed provider CLIs
remain separate. The application never downloads or runs a global bridge.

| Bridge | Upstream | Cuckoding build | Native runtime |
| --- | --- | --- | --- |
| Codex | `@agentclientprotocol/codex-acp` 1.13.1 | `1.13.1+cuckoding.2` | Codex 0.146.0 |
| Claude | `@agentclientprotocol/claude-agent-acp` 0.81.2 | `0.81.2+cuckoding.1` | Claude Code 2.1.142 |

From the repository root, with Node and Bun **1.3.10** available:

```sh
rtk env -u CR_PAT npm --prefix agent_bridges ci --ignore-scripts --omit=optional --userconfig=/dev/null --registry=https://registry.npmjs.org
rtk node --test agent_bridges/harden.test.mjs
rtk node agent_bridges/build.mjs
```

The macOS arm64/x64 build produces standalone executables and a SHA-256/version
manifest in ignored `priv/agent_bridges/`. End users need neither Node nor Bun.
`desktop/build.sh` performs the same steps before packaging. Missing, modified,
symlinked or writable-by-others bridge files fail closed at launch. Application
bundle signing and distribution provenance remain separate release gates.
`desktop/sign.sh` verifies bridge hashes before signing, gives the Bun executables
the existing JIT entitlement, and refreshes their hashes before signing the app
resource seal. The release verifier checks the packaged manifest; stale hashes
and symlinked bridge files are rejected.

`harden.mjs` verifies exact upstream file hashes before applying these changes:

- Codex exposes only true read-only and worktree-write modes, never approves
  permissions automatically, denies network access and extra temporary-directory
  writes, and requires the application's explicit native executable and argv.
  It forwards the stage's native output schema on every prompt and omits the
  upstream `cwd_relative_turn_diffs` override unsupported by Codex 0.146.0,
  preserving Cuckoding's own feature restrictions.
- Claude reads only the immutable run-owned settings file. It cannot import
  project/personal settings or managed environment variables into the bridge;
  native Claude policy still applies. It exposes only Plan and DontAsk modes,
  uses the new attempt's saved mode on load, and forwards native structured
  results as separate ACP messages.

Both builds disable Bun's automatic `.env`, `bunfig.toml`, `tsconfig.json` and
`package.json` loading. Version probes run with a minimal environment in a
directory containing hostile configuration canaries. No credentials or prompt
are used by these build checks.

The bridge packages are Apache-2.0; generated `THIRD-PARTY-NOTICES.txt` retains
dependency notices, including the Claude Agent SDK's own terms reference.
[Bun's pinned notice](BUN-LICENSE.md) lists its runtime and linked components.
Build inputs are copied into `priv/agent_bridges/build-source/`, and the lockfile
retains upstream tarball integrity. To rebuild using a modified/relinked Bun,
copy those inputs to `agent_bridges/` in an editable checkout, follow the Bun
notice's source instructions, and set `BUN_BIN` to that executable
when running `build.mjs`. The version must still identify the reviewed 1.3.10
baseline. Native signing/notarization and redistribution evidence are recorded
separately from local build or fixture success.
