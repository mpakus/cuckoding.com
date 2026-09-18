# Read-only Filesystem MCP Plugin (`mcp_server`)

## Role

This bundled reference shows how a maintained stdio MCP server becomes
run-scoped adapter configuration. It exposes only read-oriented tools for the
current worktree. It is optional and never discovered from user-global runtime
configuration.

## Pinned implementation

- Package: `@modelcontextprotocol/server-filesystem@2026.8.31`.
- Repository: `modelcontextprotocol/servers`, maintained by the official MCP project.
- npm integrity: `sha512-kKaFkyAh6oipvc9+EAbJ552JafnMnOq5nzmzWkp1jJdBhTAAGpmIpWihUG1+rfNhmEFM98gUZDdCHCDD4v6a7Q==`.
- Verified: 2026-09-18 against the npm registry and official repository.

The generated `npx` invocation is exact-version and `--offline`; Cuckoding does
not auto-install a missing package. A separate reviewed installation step must
populate and verify the package cache against the recorded integrity before
enablement. The obsolete archived `@modelcontextprotocol/server-github`
example is intentionally not used.

## Permission and tool boundary

The manifest declares one read path (`${RUN_WORKTREE}`), no write paths, no
secrets, and no network. The allowlist contains only file reads, directory
listings, metadata, and search. Adapter configuration rejects any requested
tool outside that list and never accepts a model-supplied command, package,
environment, integrity, or root path.

The server still runs as a host process, not in a sandbox. Its allowlist and
declared worktree root constrain the runtime configuration and approval; they
do not claim OS-level filesystem confinement.
