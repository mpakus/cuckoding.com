# R040f — Preview selected documents for Speculator

Status: complete on local main. Owner: Codex. Implementation: `fc5a7c1`.
Merged feature branch deleted; no remote publication.

- Audit current component/state ownership and distinguish implemented setup and
  planning from the target battle architecture in docs and contributor guidance.
- Preview up to four explicitly selected Arena-relative Markdown/text files:
  4,096 bytes each, 12,000 total. Reuse pinned descriptor-relative native reads;
  reject traversal, symlinks, hardlinks, non-regular files and invalid text.
- Persist scoped, immutable text/hash snapshots and metadata-only events using
  the existing command ledger, cancellation and non-replayed interrupted claims.
- Show exact snapshots before separate provider consent. Freeze their reference
  with the brief/team/model request; refuse foreign, failed or expired previews.
  Send only those snapshots as untrusted reference text over stdin; keep the
  existing empty-scratch/no-tools grant and proposal import provenance.
- Preserve entered text and invalidate consent when the selected snapshot changes.
  Verify focused domain, native transport/path, LiveView and packaged browser
  behavior plus restart persistence. Update docs, AGENTS and README, then merge
  verified local main and delete the merged branch without publishing.

Accepted Markdown specs, per-task citations, directory crawling, custom planning
roles, dependencies and battle execution remain separate checklist items.
