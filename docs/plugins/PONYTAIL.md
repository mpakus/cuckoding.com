# Ponytail Plugin (`instruction_skill`)

## Role

Repository contributors and agents use Ponytail for every change and review, in full mode by default. The product integration described here remains an optional, replaceable instruction-skill plugin so Cuckoding still works when the external package is absent. Neither use may weaken safety, correctness, accessibility, observability, or trust boundaries.

## Manifest highlights

- `kind: instruction_skill`; detect the upstream skill package at a pinned version, or vendor a reviewed copy with license recorded.
- Permissions: none beyond injection.
- Scopes: role, stage.

The bundled reviewed package is adapted from upstream 4.10.0 under MIT; its
reviewed upstream SHA-256 and notice ship beside the manifest. The runtime
adapter requires an exact stage capability, accepts only `lite` or `full`, and
refuses any requested waiver of the policy overlay.

## Suggested product activation

This table configures workflows orchestrated by the product. It does not override the mandatory repository contributor rule in `AGENTS.md`.

| Role/stage | Mode |
| --- | --- |
| Specification | Lite or off |
| Implementation | Full |
| Test creation | Lite |
| Security review, accessibility review, incident work | Off |

## Policy overlay

When active, task acceptance criteria, accepted decisions, authentication/isolation/redaction/audit controls, durable state and recovery, tests for critical transitions, accessible alternatives, diagnostic telemetry, and migration obligations remain mandatory. "Simpler" means less accidental complexity within these constraints.

## Evaluation

Compare similar implementation tasks with and without the skill using changed lines, dependencies, review findings, rework, tests, and duration. A smaller unsafe change is a failure.
