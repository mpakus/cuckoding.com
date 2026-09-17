# XERJ Plugin (`knowledge_backend`)

## Role

XERJ is an optional local code-index and memory backend exposed to Cuckoding through the `KnowledgeBackend` behaviour. It adds lexical code search by default and can add explicitly configured neural retrieval and namespaced memory recall on top of the built-in file/index retrieval. The core must remain fully functional without it.

## Manifest highlights

- `kind: knowledge_backend`; detect a pinned `xerj` binary and version.
- Permissions: `host_process: true`, `read_paths: ["${RUN_WORKTREE}", "${PROJECT_REPO}"]`, `network: loopback`. External network access is not required.
- Capabilities: `knowledge.index_code`, `knowledge.search_code`, `knowledge.recall`, `knowledge.write_candidate`.

## Behaviour mapping

- `index/2`: schedule incremental indexing of the trusted worktree or repository (for example `rtk xerj autoindex <folder> --no-graph` on the current upstream version); record repository SHA and index revision; ignore `.git`, secrets, dependency trees, hidden paths, and denied paths. Keep the node data and autoindex journal outside every indexed tree.
- `search/3`, `recall/3`: bounded queries validated by the core (namespace, size, result count, path scope); results are typed records with provenance and are marked untrusted.
- `write_candidate/3`: writes go to the project candidate space only; global namespaces are written by the core after approval.
- `health/1`: version, index freshness, latency.

## Namespaces

`project:<id>:code`, `project:<id>:memory`, `board:<id>:memory`, `global:patterns`, `global:skills`. Namespaces are derived from server-side IDs, never from model text. Cross-project retrieval is refused unless the project opted into global namespaces.

## Failure behavior

Timeouts return a degraded result; repeated failures open a circuit breaker and mark the plugin unhealthy; index corruption quarantines the index and offers rebuild; SQLite holds enough provenance to rebuild approved memory from knowledge files.

## Metrics

Query count, latency, hit count, selected results, context bytes. Tokens avoided are estimates and labeled.

## Operational baseline

- Bind the node to loopback. `--insecure` is acceptable only while all listeners remain loopback-only.
- The upstream default embedding mode is lexical. Do not label it semantic or neural; a neural backend requires separate configuration, prefix, and verification.
- Run `autoindex --dry-run` before indexing. Exit code `3` with `reason=completed-with-junk` means the corpus was indexed and skipped files were recorded; exit code `4` means the estimate needs an explicit decision and nothing was indexed.
- Use distinct prefixes and state directories per project and peer corpus. See `docs/REFERENCE_CODING.md` and `docs/reference-corpus.yml`.
