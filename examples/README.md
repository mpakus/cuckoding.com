# BOSS reference coding

Read-only source snapshots live here. URLs, full commit SHAs and root licenses
are pinned in [repositories.json](repositories.json). Agetor and Kander were
already present; agent-orchestrator and Backlog were cloned on 2026-10-25.
The checkouts are ignored by the parent repository; this guide and manifest are
kept in version control. `.xerjignore` excludes these operational files from the
source index; adding a root README to an existing multi-repository index otherwise
caused ambiguous dataset assignment in xerj rc.98.
Findings: [../docs/RESEARCH.md](../docs/RESEARCH.md).

## Search before implementation

Use the existing local xerj node at `http://localhost:9200`. The reference index
is named `bossrefs`; it is separate from the pre-existing `ax` index. Index data
and journals live outside this repository. Keep authentication enabled; xerj
discovers the local node key without putting its value on a command line.

```sh
rtk proxy env XERJ_DISABLE_FEEDBACK=true xerj autoindex ./examples --prefix bossrefs --no-graph --no-semantic --workers 4 --yes
rtk proxy xerj search --prefix bossrefs 'dependencyReasons' -k 3 --full 1800
rtk proxy xerj search --prefix bossrefs 'verifyClosureHead' -k 3 --full 1800
rtk proxy xerj def --prefix bossrefs mapCodexEvent
rtk proxy xerj autoindex map --prefix bossrefs --json
```

This is the **local-folder** workflow (`autoindex` + `search`/`def`), not the
separate `corpus add` + `code` workflow. It searches `./examples` directly and
avoids making another set of clones under `~/.xerj-code`.

1. State the problem and search for concrete domain terms or a known symbol.
2. Read the returned implementation, its callers and relevant tests. Search is
   lexical; no neural embeddings or cloud model are required for indexing.
3. Check that the checkout SHA still matches the manifest. Follow exact commit
   links in RESEARCH.md; upstream `main` is not the recorded evidence.
4. Record query, file:line, SHA, adopted idea and rejected complexity in `.worklog/`.
5. Implement the smallest BOSS-specific behavior and verify it with a focused
   test. Do not import competitor modules or execute their setup scripts.

If retrieval is empty or weak, use `rtk proxy rg` in the reference checkout and
official versioned docs. Some migration SQL, PDF, archive and binary files were
not indexed; read relevant source files directly rather than treating a miss as
absence. Do not scan the entire home folder or authentication directories.

## Reproduce the checkouts

For each **missing** directory in the manifest, clone its URL, fetch its full
recorded commit if needed, and check out that commit detached. Example:

```sh
rtk git clone --depth 1 https://github.com/osmove/backlog.git examples/backlog
rtk git -C examples/backlog fetch --depth 1 origin 3580cfbbb1be4144a5cca5b49190e1f8158e4cf7
rtk git -C examples/backlog checkout --detach 3580cfbbb1be4144a5cca5b49190e1f8158e4cf7
```

Do not run clone over an existing checkout or reset/clean local changes. When an
upstream refresh is needed, inspect status first, record the new SHA and license,
update affected research links, then re-run autoindex. Normal reruns reconcile
changes; `--fresh` is not a routine update flag for this generated index.

If the node is stopped, start an authenticated local xerj node with its existing
data directory. On another machine, create a persistent data directory **outside**
`examples/`, bind to loopback, and reindex. Do not delete unrelated indices.

License labels are observations from the root LICENSE files, not blanket
permission for every vendored file. Check the exact file before source reuse.
No competitor code was copied into BOSS during research.
