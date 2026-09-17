---
name: rtk-optimization
description: Work on the RTK shell-filter plugin or report its analytics.
---

# RTK Plugin

- Validate policy on the underlying command, not the wrapper; preserve exit codes and failure lines.
- Import analytics idempotently; store raw/compact bytes, estimated tokens, filter version, estimation method.
- Report coverage ratio; label all savings as estimates.
