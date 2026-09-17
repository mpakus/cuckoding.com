# Documentation Audit

Audited on 2026-09-17 against the planning-pack working tree at `b101eee347e6b19d53209decd7504d1f61a94a85`. This is a documentation and configuration audit, not evidence that the product has been implemented.

## Scope and method

Every file under `docs/` was inspected. Cross-references were checked against the root `README.md`, `AGENTS.md`, 49 numbered task files, and the worklog templates because those files define how the documentation is executed.

| Class | Files | Result |
| --- | ---: | --- |
| Core product, architecture, operations, security, audit, and reference-coding specifications | 22 | Read in full |
| Reference plugin specifications | 3 | Read in full |
| Repository skills | 13 | Read in full |
| Agent role prompts | 4 | Read in full |
| YAML configuration examples and reference-corpus manifest | 6 | Parsed successfully |
| Finder metadata | 2 | Excluded from content review; `.DS_Store` is not product documentation |

The 48 substantive files are readable and mutually reinforcing. The specifications consistently preserve the most important boundaries: SQLite is durable truth, events are persisted before broadcast, host execution is not described as a sandbox, secrets stay out of agent processes, release actions remain host-side and human-approved, project knowledge requires reviewed publication, and sleep gaps are reconciled separately from crashes.

## Findings

### P1 — Pack paths do not match the current checkout

`README.md`, `AGENTS.md`, and `docs/SKILLS.md` correctly describe `.agents/skills/` and `.cuckoding/` as repository-root directories. In this checkout those directories are under `docs/`. The pack is internally coherent only after those directories are promoted to the implementation repository root. Until then, skill discovery and example configuration paths do not match the execution instructions.

Decision required before Phase 01: either promote `docs/.agents/` and `docs/.cuckoding/` to the repository root, or deliberately revise the configuration contract and every path reference. Do not maintain both copies.

### P1 — Generic GitHub MCP example is not reproducibly pinned

`docs/.cuckoding/plugins/mcp-github-readonly/plugin.yml` invokes `npx -y @modelcontextprotocol/server-github` without an exact reviewed version or artifact digest. That permits upstream code to change between otherwise identical runs and conflicts with the pack's provenance and trusted-configuration model.

Do not enable this example until task 0803 selects a maintained implementation, pins an exact version and integrity evidence, declares external-network access, and proves the tool allowlist in conformance tests.

### P2 — XERJ search mode and transport needed precision

The previous XERJ plugin text called all retrieval semantic even though the current server defaults to lexical embeddings. It also declared `network: false` while using a loopback HTTP service. The plugin and reference-coding documents now distinguish lexical from neural retrieval and declare loopback-only transport. External network access remains prohibited for the local backend.

### P2 — Release handoff omitted its secret-store dependency

Task 0504 consumes `SecretStore` but originally depended only on 0503 and 0301. Its dependency list now includes 0204 so the credential boundary exists before host-side push and pull-request work.

### P2 — Recovery percentage is underspecified

Tasks 0203 and 1002 use a 95% recovery target but do not define a fixture count, failure matrix, confidence rule, or whether retries change the denominator. Before implementing those gates, define a deterministic drill matrix and report numerator, denominator, failure classes, and retries. A percentage over a tiny or changing sample is not release evidence.

### P3 — Generated task prose needs cleanup

Forty-one task objectives end with a doubled period and most repeat the first scope sentence verbatim. This does not change requirements, so it was left as low-risk editorial debt instead of producing a broad mechanical diff.

### P3 — Supplementary visual has no provenance link

The repository-root `inspire.jpg` is a dark AI/automation landing-page reference image and is not referenced by the product or UI documents. It is outside `docs/`, but its intended use, source, and license should be recorded before any design is derived from it or the asset is distributed.

## Deferred decisions that are not contradictions

- Tauri versus the documented native-shell fallback remains a Phase 00 spike outcome.
- Container runners and remote workers remain post-MVP plugin boundaries; the host runner is intentionally not called a sandbox.
- Optional XERJ, RTK, Ponytail, and MCP integrations do not weaken core availability requirements.
- Exact provider costs, model capabilities, signing flow, and packaging commands are intentionally revalidated during their implementation tasks.

## Readiness conclusion

The pack is a strong implementation specification, but it is not yet an implementation repository. Phase 00 can proceed now. Phase 01 should not start until the root-path decision is resolved and the Phase 00 product, runtime, shell, and sleep/wake spike evidence is recorded. The unpinned MCP example must remain disabled until task 0803.
