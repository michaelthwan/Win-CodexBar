# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` holds the repository guidelines (project state, coding style, commit/PR rules, Winget release notes).
Read it first; this file adds commands and the cross-file architecture it does not cover.

## Fork notes

This checkout is a personal fork of `nesszer/Win-CodexBar` (remote `upstream`), synced by merging `upstream/main`.
Keep fork-only work out of upstream files so merges stay conflict-free:
- `extras/` holds fork-only add-ons (e.g. `extras/rainmeter/`, a skin reading the app's PowerToys status pipe).
- `rust/src/updater.rs`: `check_for_updates_with_channel` is patched to return `None` (no auto-download of
  prebuilt binaries). Re-check it after every upstream merge.
- Build locally from this tree (`pnpm --dir apps/desktop-tauri run tauri:build`); do not use
  `scripts/windows-release-build.ps1`, which clones upstream and drops the updater patch.
- Never push `v*` tags to origin: they trigger `.github/workflows/release.yml` on the fork.
- The root `.gitignore` ignores `*.ps1`; scripts under `extras/` need a local `!*.ps1` re-include.
- `apps/desktop-tauri/src/lib/paceBudget.test.ts` fails outside UTC (timezone-dependent test); run with `TZ=UTC`.
- Dated handoff notes from past syncs live in `extras/handoffs/`.

## What this is

Win-CodexBar is a Windows tray app (Tauri 2 + React 18) that shows usage/quota for ~49 AI providers, plus a
standalone `codexbar` CLI. It is a port of the macOS CodexBar; much of `docs/` describes the upstream Swift app and
is historical unless the task is about upstream parity.

## Commands

Cargo workspace root is the repo root (`rust` + `apps/desktop-tauri/src-tauri`); default member is the Tauri crate.
The frontend uses **pnpm** (`packageManager` in `apps/desktop-tauri/package.json`; CI uses pnpm).

```powershell
.\dev.ps1                      # build + launch desktop shell (debug); -Release, -SkipBuild, -Verbose
pnpm --dir apps/desktop-tauri run tauri:dev
pnpm --dir apps/desktop-tauri run tauri:build   # release exe; raw cargo build --release still points at the dev URL

# Rust tests / lint (CI runs all of these, clippy with -D warnings)
cargo test -p codexbar
cargo test -p codexbar-desktop-tauri
cargo test -p codexbar providers::claude          # single module / test-name filter
cargo fmt --all
cargo clippy -p codexbar --all-targets -- -D warnings
cargo clippy -p codexbar-desktop-tauri --all-targets -- -D warnings

# Frontend
pnpm --dir apps/desktop-tauri test                                   # vitest run
pnpm --dir apps/desktop-tauri exec vitest run src/surfaces/TrayPanel.test.tsx
pnpm --dir apps/desktop-tauri run build          # tsc --noEmit + vite build (prebuild runs check-locale)

# CLI
cargo run -p codexbar -- usage -p claude
cargo run -p codexbar -- diagnose --pretty
```

Version lives in `version.env` (`MARKETING_VERSION`, `BUILD_NUMBER`) and must match `rust/Cargo.toml`,
`apps/desktop-tauri/package.json` and the Tauri crate (`scripts/release-doctor.ps1` checks this). Local release
builds: `scripts/windows-release-build.ps1`.

## Architecture

**Two crates, one backend.** `rust/` (`codexbar` lib + CLI binary) owns all domain logic: providers, settings,
credentials, cookie extraction, locale, tray-icon rendering. `apps/desktop-tauri/src-tauri` is a thin shell that
depends on it and exposes it to the React UI. Do not put provider logic in the shell.

**Provider pipeline.**
- `rust/src/core/provider.rs`: `ProviderId` enum (CLI names, display names, cookie domains, aliases) and the
  `Provider` trait (`fetch_usage(&FetchContext) -> ProviderFetchResult`, available `SourceMode`s: OAuth/web/CLI/...).
- `rust/src/core/provider_factory.rs`: the single `match` from `ProviderId` to implementation, re-exported as
  `codexbar::core::instantiate_provider`. Both the CLI and the Tauri shell go through it.
- `rust/src/providers/<name>/`: one module per provider (fetch, parse, auth). Multi-source providers (e.g. `claude/`
  with `oauth.rs`, `web_api.rs`, `admin_api.rs`) pick a source per `FetchContext`.
- Shared result types: `core/usage_snapshot.rs`, `core/rate_window.rs`, `core/usage_pace.rs`, cost scanning in
  `cost_scanner.rs` + `core/jsonl_scanner.rs`.
- Adding a provider touches: `ProviderId` (+ its tables/tests), the factory, `providers/mod.rs`, and on the frontend
  `components/providers/providerIcons.ts`, `components/charts/chartPalette.ts`, `test/providerCatalog.ts`.

**Secrets.** API keys, manual cookies and token accounts are stored via `rust/src/settings/` (`api_keys.rs`,
`manual_cookies.rs`) and `core/token_accounts.rs`, protected with DPAPI (`secure_file.rs`). Browser cookie import is
in `rust/src/browser/` and is opt-in per provider. Use `core/redactor.rs` when logging.

**Tauri shell (`apps/desktop-tauri/src-tauri/src`).**
- `main.rs` registers every command in `generate_handler![...]`; commands live in `commands/*.rs`.
- Backend -> UI push uses event names in `events.rs` (`provider-updated`, `refresh-started/complete`,
  `surface-mode-changed`, `locale-changed`, ...). `auto_refresh.rs` drives periodic fetches.
- Windows are "surfaces": `surface.rs` is a state machine over `SurfaceMode` (hidden / tray panel / pop-out /
  settings); `shell/` and `window_positioner.rs` handle placement, DWM effects and geometry persistence
  (`geometry_store.rs`). `floatbar/` is a separate floating-bar window.
- `tray_bridge.rs` / `tray_menu.rs` render the native tray icon via the shared renderer in `rust/src/tray/`.

**Frontend (`apps/desktop-tauri/src`).** `lib/tauri.ts` is the typed wrapper over `invoke` for every command; types
mirror Rust structs in `types/bridge.ts` (keep both sides in sync when changing a command payload). Top-level views
are in `surfaces/` (`TrayPanel`, `PopOutPanel`, `Settings`).

**Localization.** Strings are keyed by `LocaleKey` in `rust/src/locale.rs` (English/Chinese tables in
`rust/src/locale/`). The frontend's `src/i18n/keys.ts` must list exactly the same keys; `pnpm run check-locale`
(also run by `prebuild`) fails the build on drift. Add a key in both places.

## CI notes

`.github/workflows/ci.yml` runs fmt, clippy and tests for both crates on Linux (`x86_64-unknown-linux-gnu`) and on
Windows MSVC, plus `pnpm run build`. Windows-only code (DPAPI, browser cookies, tray) must still compile and pass
clippy on the Linux target, so gate it with `cfg(windows)`.
