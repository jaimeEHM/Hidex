# Changelog

All notable changes to **Hidex** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- Additional HID++ touchpad WPIDs beyond the documented T650 profile
- Notarized Developer ID builds (optional maintainer path)

## [2.0.0] — 2026-10-24

### Added

- Product rebrand to **Hidex** (independent brand; Logitech T650 referenced only as compatible hardware)
- Bilingual UI (Spanish default; English when the OS preferred language is English)
- Custom menu-bar icon (touchpad silhouette + charge bar) with live **battery %** title
- Version shown in the menu bar menu and About dialog (`CFBundleShortVersionString` + build)
- `CHANGELOG.md`, `VERSION`, brand research (`Docs/BRAND.md`)
- User self-sign helper `scripts/self-sign-installed.sh` for a stable local Accessibility identity
- Universal installer artifacts under Releases (`Hidex-*-universal.dmg` / `.pkg`)

### Changed

- Bundle ID → `com.jimmks7.hidex`
- Log file → `~/.hidex.log`
- Signing identity CN → `Hidex Local`
- Repository home → `https://github.com/jimmks7/Hidex`
- Documentation fully bilingual (ES first, then EN)

### Removed

- Product name “T650 Gestures” / bundle `com.t650.gestures` (breaking for Accessibility TCC entries — re-grant permissions after upgrade)

## [1.1.0] — 2026-10-24

### Added

- Universal (arm64 + x86_64) DMG/PKG packaging
- Gesture Lab, configurable 1/2-finger taps
- Dual HID++ raw mode (native 1–2 finger move/scroll + app-owned 3/4 finger gestures)
- Spaces via System Events; Mission Control via Mission Control.app
- MIT license, NOTICE, LEGAL notes

### Notes

- Published briefly under a previous account/name; superseded by Hidex 2.0.0

[Unreleased]: https://github.com/jimmks7/Hidex/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/jimmks7/Hidex/releases/tag/v2.0.0
[1.1.0]: https://github.com/jimmks7/Hidex/releases/tag/v1.1.0
