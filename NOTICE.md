# Notices and attributions

This project is **original user-space software** for macOS. It is **not** affiliated with, endorsed by, or sponsored by Logitech, Apple, or the maintainers of the projects listed below.

## Protocol documentation (not copied source)

The HID++ 2.0 / TouchPadRawXY (`0x6100`) behaviour was implemented from publicly available documentation and community write-ups, including:

- [Logitech cpg-docs HID++ 2.0](https://github.com/Logitech/cpg-docs/tree/master/hidpp20) (public protocol overview)
- [TouchPadRawXY 0x6100 PDF](https://lekensteyn.nl/files/logitech/6100_touchpadraw.pdf) (Peter Wu / lekensteyn collection of Logitech docs)
- Broader HID++ notes at [lekensteyn.nl/logitech.html](https://lekensteyn.nl/logitech.html)
- Linux kernel HID++ behavioural notes (GPL driver) — used only as **interoperability reference**, not as copied source

These materials describe wire formats. This repository does **not** redistribute Logitech firmware, SetPoint, Options+, or other proprietary binaries.

## Related open-source projects (inspiration / reference — not vendored)

| Project | License | Relationship |
|---------|---------|----------------|
| [Solaar](https://github.com/pwr-Solaar/Solaar) | GPL-2.0-or-later | Linux HID++ device manager. Used as **behavioural reference** for feature IDs and battery status; **no Solaar source was copied** into this tree. |
| [libratbag](https://github.com/libratbag/libratbag) | MIT | Linux gaming-device configuration; HID++ backend documentation as context. |
| [OpenLogi](https://openlogi.org/) docs | Project docs | Feature descriptions (e.g. battery 0x1000) used as reference. |
| Instant Space Switcher / spaceSwitcher / community Spaces notes | Various | Empirical notes that System Events `⌃←/→` works on modern macOS; **no private framework source was copied**. |

If you modify this project by **copying GPL code** (e.g. from Solaar), you must comply with that license (typically distributing your derivative under GPL as well). The current MIT-licensed tree avoids that by keeping an independent implementation.

## Trademarks

“Logitech”, “Unifying”, “T650”, “macOS”, “Mission Control”, and “Launchpad” are trademarks of their respective owners. Used here only for interoperability identification.

## macOS private / undocumented behaviour

Switching Spaces via System Events and optional Dock-swipe experiments rely on OS behaviour that Apple does not fully document. That does not grant rights to redistribute Apple frameworks. This app links only **public** frameworks (`Cocoa`, `IOKit`, `SwiftUI`, `ApplicationServices`).
