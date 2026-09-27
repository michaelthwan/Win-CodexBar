# CodexBar Usage (Rainmeter skin)

Fork-only extra. A small illustro-style Rainmeter panel showing the Claude, Codex and
Grok quota windows from the CodexBar desktop app, one group per provider: logo, name and
data age, then each quota window with time to reset, percent used and a brand-coloured bar.

It reads the app's cached snapshot from the named pipe `\\.\pipe\WinCodexBar.Status`,
so it makes no provider API calls of its own and cannot trigger rate limits.

## Setup

1. In CodexBar: **Settings > Advanced > PowerToys status pipe** on, then restart the app.
2. Install the skin (junction into `Documents\Rainmeter\Skins`, so `git pull` updates it):

```powershell
powershell -ExecutionPolicy Bypass -File extras\rainmeter\install.ps1
```

Uninstall with `-Uninstall`. Right-click the panel > **Refresh now** to re-read immediately.
Hover a row for the exact reset time. Bars turn red at 90% or more; the header says
"refresh failed" (hover for the reason) when the app's last refresh of that provider failed.

## Files

- `CodexBarUsage/CodexBarUsage.ini` - layout and measures
- `CodexBarUsage/@Resources/read-status.ps1` - reads the pipe, prints one JSON line
- `CodexBarUsage/@Resources/usage.lua` - parses the snapshot, lays out up to 3 groups / 8 rows
- `CodexBarUsage/@Resources/Settings.inc` - poll interval (`FetchSeconds`)
- `CodexBarUsage/@Resources/icons/*.png` - logos rendered from `rust/src/cli/serve/dashboard/icons`
  by `tools/render_icons.py` (headless Edge + Pillow); re-run it if upstream changes a logo

The pipe payload is defined in `apps/desktop-tauri/src-tauri/src/powertoys.rs`; if upstream
changes its field names, update `usage.lua`.
