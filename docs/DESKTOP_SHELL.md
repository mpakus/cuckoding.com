# Desktop Shell

## Requirement

After installation the user launches Cuckoding like any app. The only native surface is a status-bar (menubar) icon with controls for the dashboard, About, Settings, logs, launch at login, updates, diagnostics, safe mode, and Quit. No dock icon, no native window. The whole interface is a Phoenix LiveView application on a loopback port.

## Options compared

| Option | What it is | Fit for "tray only + browser UI" | Packaging, signing, updates | Native code | Notes |
| --- | --- | --- | --- | --- | --- |
| **Tauri 2, tray-only** | Rust shell, `ActivationPolicy::Accessory`, `TrayIconBuilder`, no webview window; bundled mix release as a resource; `open` default browser | Exact fit | `tauri build` produces the `.app`, signs, notarizes; `tauri-plugin-updater` for updates | Rust (small) | Uses the same Tauri machinery as v1 minus the webview. Well-trodden path for menubar apps |
| **Swift/AppKit shell** | ~300 lines: `NSStatusItem`, `NSMenu`, `Process` for the release, `NSWorkspace.open` | Exact fit | Xcode project; sign/notarize via `xcodebuild`/`notarytool`; updater via Sparkle | Swift | Smallest binary and most native; requires maintaining an Xcode project and Sparkle |
| **elixir-desktop** | Elixir library wrapping `:wx`; renders menus and a taskbar icon from Elixir; has a browser backend fallback and `mix desktop.installer` | Fits if only the wx taskbar icon is used and no window is opened | Ships OTP built with `wx` plus wxWidgets libraries; installer support exists; signing/notarization is manual | None (Elixir only) | Zero non-Elixir code, but drags wxWidgets into the bundle and depends on wx taskbar behaviour on macOS, which the project's own guide flags as recently improved. Good fallback if native code is unwanted |
| **Burrito** | Zig wrapper producing a single self-extracting binary of a mix release | Does not provide a tray icon or `.app`; it is a packaging tool, not a shell | Single Mach-O; payload extracted to Application Support at first run; the extracted runtime lives outside the signed bundle | Zig (build only) | Wrong tool for the shell. Useful later for a headless `cuckoding serve` binary on Linux/servers |

Burrito and elixir-desktop are not alternatives to each other: one packages, the other provides native UI. For an `.app` bundle, a plain mix release directory inside `Contents/Resources` is simpler and signs cleanly; Burrito's self-extraction adds nothing there.

## Decision (ADR-011)

Primary: **Tauri 2 in tray-only mode**, confirmed by task 0003 on 2026-09-17. Fallbacks remain documented so the boundary stays stable: Swift/AppKit shell if the Rust toolchain is unwanted, elixir-desktop if native code is unwanted. The Phoenix side never depends on which shell is used; the shell contract below is the only interface. Measured evidence and remaining signing gates are in `docs/MENUBAR_SHELL_SPIKE.md`.

The production shell is under `desktop/`. Developers run
`rtk ./bin/dev.build`, which delegates to `desktop/build.sh`, builds the Phoenix
release, runs the pinned Rust checks, creates the local unsigned `.app`, and
executes the sterile-environment protocol verifier. Signing, notarization, and
distribution policy are in `docs/DISTRIBUTION.md`.

The icon source is `desktop/icon.svg`: a circular violet capital C with a sperm
tail flowing left on a pearl tile. App PNG/ICNS, browser icons and web/sidebar marks use that source.
The status item embeds its tile-free 64 x 64 monochrome silhouette. macOS supplies
the foreground color for light and dark menu bars; the shell reads raw RGBA
bytes directly, so no runtime image decoder or additional dependency is required.
After changing the vector, run
`rtk env -u GEM_HOME -u GEM_PATH /usr/bin/ruby desktop/export_icons.rb`.
The exporter uses `rsvg-convert`, ImageMagick and macOS `iconutil`; all outputs
are committed, so ordinary release builds do not need these artwork tools.

## Shell contract

1. Resolve the bundled release path and application data directory.
2. Pick a free loopback port; generate a 32-byte bootstrap token.
3. Write a per-launch Phoenix session-signing secret and the bootstrap token to a unique mode-0600 file under the application data directory. Launch `bin/cuckoding start` with an allowlisted environment containing `CUCKODING_PORT`, `CUCKODING_BOOTSTRAP_FILE`, and `RELEASE_DISTRIBUTION=none`. Never place credentials in argv, commit a cookie-signing secret, or enable Erlang distribution.
4. Phoenix reads and deletes the bootstrap file, binds only to `127.0.0.1`, then writes one exact stdout line: `READY {"port":…, "version":…}`. On timeout, malformed readiness, or early exit, terminate the child group and show diagnostics with "Open logs" and "Quit".
5. Menu items:
   - **Cuckoding** → `GET /open?token=<one-time>` in the default browser; Phoenix exchanges it for a session cookie and redirects to the dashboard. Tokens are single-use with a short TTL; the shell requests a fresh one from `POST /shell/tokens` using the bootstrap credential.
   - **About** → native panel with version, release notes link, and the port.
   - **Settings** → browser `/settings/plugins` via the same token flow.
   - **Launch at Login** → the native macOS 13+ `SMAppService.mainApp`
     registration. The checkmark reflects the system status. A pending approval
     opens System Settings; registration failures are shown as unavailable.
   - **Export Diagnostics** → authenticated `POST /shell/diagnostics`; after
     validating that the returned regular file remains inside the application
     data diagnostics directory, reveal it in Finder for user review.
   - **Quit** → `POST /shell/shutdown`; Phoenix pauses admission and hibernates active runs before accepting shutdown. A failed hibernate returns a conflict and keeps the release alive. After acceptance the shell waits three seconds, then sends `SIGINT`, `SIGTERM`, and `SIGKILL` to the child process group as needed. Shell `SIGINT` and `SIGTERM` use the same policy path.
6. Status line: poll `GET /shell/status` every few seconds for active runs and attention items; render as menu text (for example "3 running · 1 needs approval").
7. **Check for Updates** uses the compile-time HTTPS endpoint and public key.
   The first click shows the exact version and schema impact; a second click
   confirms that version. Tauri verifies the downloaded bundle signature
   before Phoenix hibernates runs and snapshots data. The shell then backs up
   the current app, stops the runtime, installs, and opens the candidate.
   Candidate migration or READY failure restores both data and the previous
   app.
8. **Restart in Safe Mode** writes a private one-shot marker and relaunches.
   Safe mode serves authenticated history while omitting every runner and
   plugin worker; the status line labels the mode explicitly.
9. Crash of the child: show "Cuckoding stopped unexpectedly" and keep the
   diagnostics action available. The MVP does not auto-restart; an explicit
   bounded restart action may be added with the updater/recovery work.

## Security notes

- The launch environment is cleared, with a fixed system PATH and app-owned
  HOME. The shell supplies `CUCKODING_RUNTIME_HOME` as a host-only hint for
  known-location executable discovery and host-side Git ignore-file lookup
  (see [repository checks](EXECUTION_ENVIRONMENTS.md#workspace-layout)). This does not load shell startup files,
  reuse personal provider profiles, expand an agent grant or reach agent child
  environments. See [executable discovery](AGENT_AUTHORIZATION_FLOW.md#executable-discovery)
  and the [safe local restart procedure](DEVELOPMENT.md#testing-one-local-instance).
- The bootstrap credential is exchanged once for a shell session; browser sessions are separate, short-lived, and cookie-based.
- `/open` tokens are single-use and expire in 60 seconds; a stolen link cannot be replayed.
- Strict host/origin checks on all shell and browser endpoints; CSRF on state-changing routes.
- Disable BEAM distribution in the desktop release. The loopback HTTP listener is the only network listener; `epmd` must not start.
- Optional user setting: require the browser session to be re-authorized after the machine wakes from sleep.
