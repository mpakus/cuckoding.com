# R090a — Claude subscription authentication decision

Decision recorded and verified; local integration pending. Branch
`feature/R090a-claude-auth-decision`, base `1d92f05`.
Ponytail full 5.3.2 MIT; adapter/security/quality guidance. Docs only.

The user selected **Subscription sign-in after Anthropic approval** in the pending
authentication question. This selects the intended path; it does not confirm
approval. The official [Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview)
was rechecked 2026-10-23. Keep the provider unavailable until its approval and
adapter conformance gates are met. No credentials, installs, provider calls,
inference, external messages or application changes were needed.

D051, adapter acceptance, Plan, AGENTS and README agree on the selected path
and the still-unconfirmed approval. Verified **211** local Markdown targets,
whitespace and an unchanged application input digest against R020s's sealed
receipt. No full suite/build rerun is warranted for this documentation-only
decision; existing application evidence is not approval or Claude acceptance.
