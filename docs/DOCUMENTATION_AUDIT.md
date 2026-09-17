# Documentation Audit

Audited on 2026-09-17 against the planning-pack working tree at `b101eee347e6b19d53209decd7504d1f61a94a85`. This is a documentation and configuration audit, not evidence that the product has been implemented.

## Scope and method

Every file in the original planning pack under `docs/` was inspected. Cross-references were checked against the root `README.md`, `AGENTS.md`, the original 49 numbered task files, and the worklog templates because those files define how the documentation is executed. Task 0006 subsequently added the 50th task and promoted the skill and configuration packs to their intended repository-root locations.

| Class | Files | Current location | Result |
| --- | ---: | --- | --- |
| Core product, architecture, operations, security, audit, reference-coding, and readiness specifications | 23 | `docs/` | Read in full |
| Reference plugin specifications | 3 | `docs/plugins/` | Read in full |
| Repository skills | 13 | `.agents/skills/` | Read in full |
| Agent role prompts | 4 | `.cuckoding/agents/` | Read in full |
| YAML configuration examples | 5 | `.cuckoding/` | Parsed successfully |
| Reference-corpus manifest | 1 | `docs/` | Parsed successfully |
| Finder metadata | 2 | `docs/`, `.cuckoding/` | Excluded from content review; `.DS_Store` is not product documentation |

The 49 substantive files are readable and mutually reinforcing. The specifications consistently preserve the most important boundaries: SQLite is durable truth, events are persisted before broadcast, host execution is not described as a sandbox, secrets stay out of agent processes, release actions remain host-side and human-approved, project knowledge requires reviewed publication, and sleep gaps are reconciled separately from crashes.

## Findings

### Resolved — Pack paths now match the checkout

`README.md`, `AGENTS.md`, and `docs/SKILLS.md` describe `.agents/skills/` and `.cuckoding/` as repository-root directories. Task 0006 promoted the misplaced packs to those paths without retaining duplicate copies.

Verification requires all 13 skills and nine configuration/role artifacts to resolve at root, with no `docs/.agents/` or `docs/.cuckoding/` directory remaining.

### P1 — Generic GitHub MCP example is not reproducibly pinned

`.cuckoding/plugins/mcp-github-readonly/plugin.yml` invokes `npx -y @modelcontextprotocol/server-github` without an exact reviewed version or artifact digest. That permits upstream code to change between otherwise identical runs and conflicts with the pack's provenance and trusted-configuration model.

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

The pack is a strong implementation specification, but it is not yet an implementation repository. Structural preparation is complete and Phase 00 can proceed. Phase 1 must wait for the Phase 00 product, runtime, shell, and sleep/wake spike evidence described in `docs/IMPLEMENTATION_READINESS.md`. The unpinned MCP example must remain disabled until task 0803.
