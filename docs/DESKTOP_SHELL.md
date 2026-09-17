# Desktop Shell

## Requirement

After installation the user launches Cuckoding like any app. The only native surface is a status-bar (menubar) icon with a menu: **Cuckoding** (open the dashboard in the default browser), **About**, **Settings** (opens the settings page in the browser), **Quit**. No dock icon, no native window. The whole interface is a Phoenix LiveView application on a loopback port.

## Options compared

| Option | What it is | Fit for "tray only + browser UI" | Packaging, signing, updates | Native code | Notes |
| --- | --- | --- | --- | --- | --- |
| **Tauri 2, tray-only** | Rust shell, `ActivationPolicy::Accessory`, `TrayIconBuilder`, no webview window; bundled mix release as a resource; `open` default browser | Exact fit | `tauri build` produces the `.app`, signs, notarizes; `tauri-plugin-updater` for updates | Rust (small) | Uses the same Tauri machinery as v1 minus the webview. Well-trodden path for menubar apps |
| **Swift/AppKit shell** | ~300 lines: `NSStatusItem`, `NSMenu`, `Process` for the release, `NSWorkspace.open` | Exact fit | Xcode project; sign/notarize via `xcodebuild`/`notarytool`; updater via Sparkle | Swift | Smallest binary and most native; requires maintaining an Xcode project and Sparkle |
| **elixir-desktop** | Elixir library wrapping `:wx`; renders menus and a taskbar icon from Elixir; has a browser backend fallback and `mix desktop.installer` | Fits if only the wx taskbar icon is used and no window is opened | Ships OTP built with `wx` plus wxWidgets libraries; installer support exists; signing/notarization is manual | None (Elixir only) | Zero non-Elixir code, but drags wxWidgets into the bundle and depends on wx taskbar behaviour on macOS, which the project's own guide flags as recently improved. Good fallback if native code is unwanted |
| **Burrito** | Zig wrapper producing a single self-extracting binary of a mix release | Does not provide a tray icon or `.app`; it is a packaging tool, not a shell | Single Mach-O; payload extracted to Application Support at first run; the extracted runtime lives outside the signed bundle | Zig (build only) | Wrong tool for the shell. Useful later for a headless `cuckoding serve` binary on Linux/servers |

Burrito and elixir-desktop are not alternatives to each other: one packages, the other provides native UI. For an `.app` bundle, a plain mix release directory inside `Contents/Resources` is simpler and signs cleanly; Burrito's self-extraction adds nothing there.

## Decision (ADR-011)

Primary: **Tauri 2 in tray-only mode**. Fallbacks documented so the boundary stays stable: Swift/AppKit shell if the Rust toolchain is unwanted, elixir-desktop if native code is unwanted. The Phoenix side never depends on which shell is used; the shell contract below is the only interface.

## Shell contract

1. Resolve the bundled release path and application data directory.
2. Pick a free loopback port; generate a 32-byte bootstrap token.
3. Launch `bin/cuckoding start` with `PHX_SERVER=1`, `CUCKODING_PORT`, `CUCKODING_BOOTSTRAP_TOKEN` passed through an inherited file descriptor or a mode-0600 file, never argv.
4. Read stdout for one line `READY {"port":…, "version":…}`; on failure show diagnostics and offer "Open logs" and "Quit".
5. Menu items:
   - **Cuckoding** → `GET /open?token=<one-time>` in the default browser; Phoenix exchanges it for a session cookie and redirects to the dashboard. Tokens are single-use with a short TTL; the shell requests a fresh one from `POST /shell/tokens` using the bootstrap credential.
   - **About** → native panel with version, release notes link, and the port.
   - **Settings** → browser `/settings` via the same token flow.
   - **Quit** → `POST /shell/shutdown` (hibernate or stop runs per policy) then termination ladder on the child process.
6. Status line: poll `GET /shell/status` every few seconds for active runs and attention items; render as menu text (for example "3 running · 1 needs approval").
7. Login item toggle and update checks live in the shell; update policy is in `docs/DISTRIBUTION.md`.
8. Crash of the child: show "Cuckoding stopped unexpectedly" with restart and diagnostics options; never auto-restart in a loop more than N times per hour.

## Security notes

- The bootstrap credential is exchanged once for a shell session; browser sessions are separate, short-lived, and cookie-based.
- `/open` tokens are single-use and expire in 60 seconds; a stolen link cannot be replayed.
- Strict host/origin checks on all shell and browser endpoints; CSRF on state-changing routes.
- Optional user setting: require the browser session to be re-authorized after the machine wakes from sleep.
