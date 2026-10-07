---
name: plugin-system
description: Add or change connector kinds, manifests, detection, permissions, health, and conformance tests.
---

# Plugin System

Plugin expansion is deferred by `docs/PRODUCT.md`; apply this skill only to explicitly scoped plugin work.

- Every kind is a behaviour with a fake implementation and a conformance suite.
- Manifests are schema-validated; permissions are declared and narrowed by scope; enabling is a user action with audit.
- Plugin output is untrusted data; numbers carry `source: measured | reported | estimated`.
- Plugin processes run under the plugin supervisor with restart limits; failures degrade the feature, never the core.
- Use the actual implemented kind (for example RTK filtering or instruction skills) as the conformance target; do not add a registry or knowledge service merely to test it.

Before completion: run the kind's conformance suite, undeclared-access tests, crash/restart tests, and the degraded-mode UI test.
