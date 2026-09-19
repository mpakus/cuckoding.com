# Task 1006 — Cursor isolation and per-agent saves

## Goal

Make the verified Cursor Agent CLI eligible only through a run-owned home and configuration tree, and let project settings create or update one agent connection without forcing unrelated role edits to validate.

## Acceptance criteria

- Cursor Agent never reads or writes the user's real Cursor or Claude configuration directories and never inherits user-global MCP configuration.
- A queued Cursor run explains and verifies run-scoped login before launch.
- Cursor launch, resume, cancellation, event decoding, usage normalization, and unsupported-plugin behavior have focused regression coverage.
- Project settings show a Save agent or Update agent action on every agent card.
- Saving one agent appends an immutable project configuration revision while preserving other saved agents and role assignments.
- An invalid or stale agent save creates no partial configuration revision and reports an accessible error.
- Existing board and run snapshots are unchanged.
- Relevant adapter, security, flow, and testing docs describe the shipped behavior without claiming unverified production evidence.

## Out of scope

- OpenCode and arbitrary custom-agent launch support.
- Copying or reusing user-global Cursor authentication.
- Enabling project or user MCP servers for Cursor.

