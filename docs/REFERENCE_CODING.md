# Reference Coding with XERJ

Reference coding is a retrieval step, not permission to copy. Before implementing an unfamiliar concurrency, worktree, process, persistence, desktop, or adapter problem, search this project and the closest licensed peer corpus. Record the useful `path:line`, explain what is being adapted, and verify that Cuckoding's stricter durability and security boundaries still hold.

The pinned corpus is declared in `docs/reference-corpus.yml`. Clones and XERJ state live outside the repository so they cannot leak into commits or recursively enter the project index.

## Local layout

| Purpose | Default location |
| --- | --- |
| Peer checkouts | `~/.local/share/cuckoding/reference-code/` |
| XERJ node data | `~/.local/share/cuckoding/xerj/data/` |
| Autoindex journals | `~/.local/share/cuckoding/xerj/autoindex/` |

The verified baseline is XERJ `v1.0.0-rc.74` in lexical mode. Lexical is the upstream default; do not call it neural or semantic retrieval. The current project index is `cuckoding-project-v4`; v3 remains a frozen documentation-only generation from before source files were added. A future neural index requires an explicit model, a distinct prefix, measured benefit, and updated evidence.

## Start the local node

All repository shell work is RTK-wrapped. The XERJ node is deliberately insecure only because it binds to loopback; never expose these ports to another interface.

```sh
rtk xerj --insecure --data-dir ~/.local/share/cuckoding/xerj/data --embed-mode lexical --disable-feedback
```

Confirm the listener is loopback-only before indexing:

```sh
rtk lsof -nP -iTCP:9200 -sTCP:LISTEN
```

## Clone the pinned peers

Read the exact revisions and licenses from `docs/reference-corpus.yml`. Clone only when a checkout is absent, then detach at the declared revision:

```sh
rtk git clone --depth 1 https://github.com/alamops/agetor.git ~/.local/share/cuckoding/reference-code/agetor
rtk git clone --depth 1 https://github.com/BloopAI/vibe-kanban.git ~/.local/share/cuckoding/reference-code/vibe-kanban
rtk git clone --depth 1 https://github.com/jpdlr/hydra.git ~/.local/share/cuckoding/reference-code/hydra
rtk git -C ~/.local/share/cuckoding/reference-code/agetor checkout --detach eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a
rtk git -C ~/.local/share/cuckoding/reference-code/vibe-kanban checkout --detach 735654971bd396aa97b65166955678e4c34f8bf8
rtk git -C ~/.local/share/cuckoding/reference-code/hydra checkout --detach d8ad56112c2c3acfb2f65f53b6890f30a25c693c
```

Revalidate the license at the pinned revision before adapting code. Keep copied material small, attributed, and compatible with Cuckoding's distribution license. When only an approach is needed, reimplement from the behavior and cite the source rather than copying text.

## Estimate, index, and refresh

Run the same command with `--dry-run` first. The estimate covers client extraction, not server indexing. Use a dedicated state directory and prefix for every corpus. Project indexing uses `--no-graph` so later runs can reconcile additions, changes, moves, and removals.

```sh
rtk xerj autoindex . --dry-run --no-graph --prefix cuckoding-project-v4 --state-dir ~/.local/share/cuckoding/xerj/autoindex/cuckoding-project-v4 --progress plain
rtk xerj autoindex . --no-graph --prefix cuckoding-project-v4 --state-dir ~/.local/share/cuckoding/xerj/autoindex/cuckoding-project-v4 --progress plain --yes
```

Use the same dry-run/actual pair for peers, substituting the checkout, prefix, and state directory from the manifest. Pinned peer revisions are immutable snapshots; index a changed revision under a new prefix and validate it before switching readers.

XERJ exit code `3` with `reason=completed-with-junk` is successful indexing with explicitly skipped files. Read the terminal `xerj-done` line: if `code_files>0` and `code_files_indexed=0`, treat the run as defective even when documents were indexed. Exit code `4` requires an explicit estimate decision and indexes nothing.

## Search before coding

Start narrow and identify the responsible symbol. Retrieve definitions when possible, then inspect the surrounding source in the pinned checkout.

```sh
rtk xerj search --prefix cuckoding-project-v4 -k 5 "event before broadcast durable state"
rtk xerj def --prefix ref-vibe-kanban-v1 -k 5 WorktreeManager
rtk xerj def --prefix ref-agetor-v1 -k 5 API_TOKEN
rtk xerj def --prefix ref-hydra-v1 -k 5 hydrateWorkspaceAgents
```

The initial retrieval proved these useful entry points:

- Agetor `src/bun/api-config.ts:24` creates a per-launch loopback API token with an environment override.
- Vibe Kanban `crates/worktree-manager/src/worktree_manager.rs:52` centralizes worktree operations. Its cleanup approach is reference material only; Cuckoding must retain stricter recorded-ownership checks before deletion.
- Hydra `electron/agents/AgentManager.ts:300` rehydrates persisted workspace agents and their provider sessions.

For every implementation decision influenced by a peer, record the repository, pinned revision, `path:line`, adapted idea, and any Cuckoding-specific constraint in the task worklog. A search hit is evidence of an implementation pattern, not evidence that the pattern is safe here.

## RTK rule

Prefix every repository shell command with `rtk`, including Git, Mix, test, format, lint, XERJ, and inspection commands. Use `rtk proxy <command> ...` only when the exact unfiltered stream is operationally required or an RTK adapter changes semantics. Product configuration continues to store the underlying command, such as `mix test`; the runtime validates that command first and applies the RTK shell-filter plugin afterward.
