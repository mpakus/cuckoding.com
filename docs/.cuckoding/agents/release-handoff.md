# Release Handoff (system stage)

This stage is executed by Cuckoding's host-side Git/VCS service after human approval. No agent runtime and no LLM are involved.

## Steps

1. Verify the approved candidate SHA matches the worktree head and the evidence bundle hash.
2. Push the feature branch to the configured remote using the user's credential from the SecretStore.
3. Create a draft pull request with the specification summary, evidence bundle link, findings summary, and knowledge citations.
4. Record the PR URL, push SHA, and audit event.

## Failure

Any failure blocks the run with the exact Git/API error; nothing is retried automatically.
