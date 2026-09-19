# Worklog — 1013 planning output ingestion

## Acceptance criteria

Ingest the installed Codex CLI's real output, keep parsing strict, and permit read-only project inspection.

## Baseline

- Branch: `fix/1013-planning-output-ingest` from `ec8adb8` on `main`.
- Reported run `01a0baf1-25c2-74a6-9870-61ce2a873b33` exited successfully but was recorded as a generic planning failure.
- Its redacted process artifact begins with the fixed Codex CLI line `Reading additional input from stdin...` before valid JSONL; the strict parser rejected that line.
- The planning prompt also prohibited commands, so Codex did not use its read-only shell to inspect `docs/TASKS.md` and cited the wrong path.
- XERJ was unavailable on loopback port 9200. Direct inspection used `lib/cuckoding/adapters/output_parser.ex`, `lib/cuckoding/board_task_intake.ex`, and the pinned peer corpus; no peer implementation was adapted.
- Ponytail 4.10.0 (MIT), architecture, adapter, LiveView, security, and quality-gate guidance are active.
- Preserved the unrelated untracked root `icon.png`.

## Implementation

- Ignore only the installed Codex CLI's exact first-line stdin prelude before
  strict JSONL decoding. Any other non-JSON line still rejects the artifact.
- Permit read-only shell inspection in the planning request while preserving
  the Codex read-only sandbox, denied network, disabled web search, and no-write
  instruction.
- Persist a specific public failure code and recovery message when a provider
  artifact cannot be decoded.
- Updated workflow, architecture, and security documentation.

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk mix test test/cuckoding/adapters/output_parser_test.exs test/cuckoding/board_task_intake_test.exs` | pass | 7 tests, 0 failures. |
| Real artifact parser check for run `01a0baf1-25c2-74a6-9870-61ce2a873b33` | pass | The previously rejected artifact now decodes to its structured task object. |
| `rtk env -u CR_PAT mix quality` | pass | 10 properties and 238 tests passed; Credo, Sobelow, and Hex audit reported no issues. Expected crash-worker fixture logs appeared. |

## Residual risk

- The reported run's proposal cited `TASKS.md` instead of the existing
  `docs/TASKS.md`, so that historical proposal remains invalid. A new run is
  required after the updated read-only inspection prompt is active.
