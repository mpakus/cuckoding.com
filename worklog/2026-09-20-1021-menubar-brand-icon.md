# Worklog — 1021 menubar brand icon

## Metadata

- Date/time (UTC): 2026-09-20
- Task: 1021
- Status: complete
- Human/agent owner: codex
- Branch: `feature/1021-menubar-icon`
- Start revision: `5d98e72`
- End revision: task commit
- Environment: macOS Apple Silicon; pinned Rust 1.90.0; Tauri 2.11.5

## Intended outcome

- Use the stakeholder-supplied `icon.png` for the native macOS status item.
- Preserve automatic light/dark menubar adaptation and keep the embedded tray bitmap small.
- Leave the shell handshake, process lifecycle, authentication, and menu behavior unchanged.

## Context inspected

- Required product, architecture, database, workflow, security, execution-environment, desktop-shell, task, and skill documentation.
- Existing `TrayIconBuilder` generated a solid 16-pixel square instead of loading artwork.
- The supplied image is a 1,254 × 1,254 RGBA owl/gear mark with transparency.
- XERJ was unavailable at `http://localhost:9200`. Direct inspection used Tauri 2.11.5 `Image::new` and tray-icon 0.24.2 macOS scaling/template behavior; both are Apache-2.0 OR MIT licensed.

## Work performed

- Tracked the supplied root `icon.png` as the canonical source artwork.
- Derived a 64 x 64 monochrome `tray-icon.rgba` template with transparent
  negative space so macOS can adapt it to light and dark menu bars.
- Embedded the 16 KiB raw bitmap with `include_bytes!` and reused Tauri's
  existing template-icon path. No decoder or new Rust dependency was added.
- Added one focused Rust regression test for dimensions, transparency, visible
  pixels, and monochrome template data.
- Documented the icon source and runtime representation in the shell contract.

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk cargo +1.90.0 fmt --manifest-path desktop/src-tauri/Cargo.toml -- --check` | pass | Rust formatting is clean. |
| `rtk cargo +1.90.0 test --manifest-path desktop/src-tauri/Cargo.toml` | pass | 10 tests, 0 failures, including the tray bitmap regression. |
| `rtk cargo +1.90.0 clippy --manifest-path desktop/src-tauri/Cargo.toml -- -D warnings` | pass | No warnings. |
| `rtk ./bin/dev.build` | pass | Built the Phoenix release and unsigned `Cuckoding.app`; all release metadata, Rust, and sterile launch/protocol checks passed. |
| `rtk env -u CR_PAT mix quality` | pass | 269 tests and 10 properties passed; Credo, Sobelow, and dependency audit reported no issues. Expected crash-fixture logs were emitted by the supervisor recovery test. |
| Derived bitmap inspection | pass | 64 x 64 RGBA, 16,384 bytes; the enlarged preview preserves the owl/gear silhouette and transparent openings. |

## Risks and blockers

- The existing installed application database has pending migrations, so the
  release shell correctly stopped before the status item remained visible.
  Sterile clean-state shell startup passed; final in-menu visual confirmation
  remains a manual packaging check after the normal update migration path.

## Handoff

Ready to merge. The application bundle is at
`desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
