# Worklog

The worklog is the durable engineering narrative for the project. It complements commits and task checklists by recording what was attempted, observed, decided, verified, and handed off.

## File naming

- Implementation session: `YYYY-MM-DD-<task-id>-<short-name>.md`
- Architecture decision support: `YYYY-MM-DD-decision-<short-name>.md`
- Incident: `YYYY-MM-DD-incident-<short-name>.md`

Use UTC timestamps inside entries. Create a new file for a materially separate session rather than continually rewriting history. Corrections should be appended and labeled.

## Required content

- Task, branch, repository revision, owner/agent session, and environment.
- Intended outcome and acceptance criteria addressed.
- Changes and artifacts produced.
- Commands/tests with exact results.
- Telemetry or operational evidence when relevant.
- Decisions, assumptions, risks, blockers, and next handoff.
- No secrets, hidden reasoning, raw authorization headers, or unnecessary personal data.

## Relationship to product worklogs

These repository files document building Cuckoding. The product itself stores normalized run events and artifacts in its database. Do not copy private chain-of-thought into either system.
