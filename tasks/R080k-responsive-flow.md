# R080k — Responsive setup-to-Start flow

Status: implemented, verified and merged locally to main, 2026-10-23 (`7942cb7`).

- [x] Inspect the rendered Agents → Team → Arena → Create tasks → Start flow at
  desktop and narrow widths using isolated profile-free development data.
- [x] Fix demonstrated clipping/overflow or inaccessible controls with shared
  LiveView components/CSS; preserve one Start, grants and dirty dialog text.
  Keep custom stages in one row and open task editing only after server selection.
- [x] Verify focused behavior, real browser reflow/keyboard/dialog checks and
  relevant quality/build checks. Record unavailable human/provider acceptance.
- [x] Update docs/AGENTS/README and merge the verified slice into local main;
  feature branch deleted. No push/publication.

This does not claim an unfamiliar user's timed ten-minute setup, screen-reader
acceptance or paid provider/battle acceptance.

Evidence: [worklog](../worklog/2026-10-23-R080k-responsive-flow.md).
