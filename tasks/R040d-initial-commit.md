# R040d — Initial commit preview and consent

Status: verified; local main integration pending. Owner: Codex. Branch: `feature/R040d-initial-commit`.

- Preview explicitly selected relative files (or an empty baseline) in a registered
  unborn standalone repository. Show paths, sizes, modes, SHA-256, branch and author.
- Require fresh, Arena-scoped confirmation bound to that exact preview. Recheck
  repository identity, branch, absent index and selected bytes before effects.
- Commit only the previewed bytes with fixed local identity/message; preserve all
  working files. Refuse existing indexes/history, unsafe paths/layouts and drift.
- Use Git plumbing with filters/hooks/signing/network disabled, private candidate
  index, exclusive index/HEAD locks and compare-and-swap of the absent branch ref.
  Never replace an existing index/ref. Retain partial effects and never replay an
  interrupted commit. No push, agent access or battle execution.
- Reuse durable commands/events and bounded native transport; cover cancellation,
  changed files/index/HEAD, path escapes, independent cleanup and expired sessions.
- Verify real Git fixtures, packaged smoke/retention and desktop/narrow browser flow.
  Update README, AGENTS and docs; merge local main and delete the merged branch.

First slice limit: 16 selected regular files, 240-byte relative paths, 1 MiB per
file and 8 MiB total. Existing staged work and richer file browsing remain manual.
