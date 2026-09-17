# 0204 — Keychain SecretStore and Redaction

## Objective

Implement `SecretStore` on macOS Keychain (via `security` CLI, with a documented path to a native library), opaque references in the database, the redaction processor for logs, events, artifacts, exports, and knowledge inputs, and secret canary fixtures..

## Dependencies

- 0201.

## Scope

Implement `SecretStore` on macOS Keychain (via `security` CLI, with a documented path to a native library), opaque references in the database, the redaction processor for logs, events, artifacts, exports, and knowledge inputs, and secret canary fixtures.

## Deliverables

- `SecretStore` behaviour, Keychain implementation, fake implementation.
- Redaction processor and canary suite.

## Checklist

- [ ] Never persist raw secrets, full environment maps, or authorization headers.
- [ ] Redact before disk, broadcast, export, and extraction.
- [ ] Agent processes receive no Cuckoding-managed secret.

## Acceptance criteria

- [ ] Canary secrets never appear in any persisted or broadcast output.
- [ ] Reference use is audited.

## Verification and evidence

Run canary tests across logs, database, UI, exports, and knowledge fixtures.
