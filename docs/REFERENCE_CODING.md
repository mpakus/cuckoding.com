# Reference coding

Use `rtk rg` and direct source inspection. No indexing service or replacement
plugin is required. Search is a short evidence-gathering step, not a separate
infrastructure project.

Before implementing an unfamiliar mechanism:

1. Search this checkout for the responsible code, callers, tests and contracts.
2. If absent, inspect the smallest relevant primary documentation or licensed
   peer implementation. Pin the peer revision; do not copy a whole framework.
3. Verify the license at that revision before adapting source.
4. Record repository/revision, `path:line`, adapted idea and the Cuckoding boundary
   that changes it (SQLite authority, host permissions, ownership or approval).
5. Add the smallest runnable regression check of the chosen behavior.

Use official current provider documentation for CLI flags, auth and model APIs;
old docs/commits are leads, not compatibility evidence. Clones stay outside this
repository and never become agent filesystem grants. Ordinary local file search
does not need a server, model, corpus build or embeddings.

Prefix shell commands with RTK. Use exact-output proxy exceptions when needed and
record them in the worklog. Never run a retrieved snippet merely because a search
found it. RTK optimizes output; it does not approve commands or prove correctness.
