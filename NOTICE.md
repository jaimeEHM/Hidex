# Notices and attributions / Avisos y atribuciones

**Hidex** is original user-space software for macOS. It is **not** affiliated with, endorsed by, or sponsored by Logitech, Apple, or the maintainers of the projects listed below.

**Hidex** es software original en espacio de usuario para macOS. **No** está afiliado ni respaldado por Logitech, Apple ni los mantenedores de los proyectos siguientes.

## Protocol documentation (not copied source)

HID++ 2.0 / TouchPadRawXY (`0x6100`) behaviour was implemented from publicly available documentation, including:

- [Logitech cpg-docs HID++ 2.0](https://github.com/Logitech/cpg-docs/tree/master/hidpp20)
- [TouchPadRawXY 0x6100 PDF](https://lekensteyn.nl/files/logitech/6100_touchpadraw.pdf) (Peter Wu / lekensteyn collection)
- [lekensteyn.nl/logitech.html](https://lekensteyn.nl/logitech.html)

This repository does **not** redistribute Logitech firmware, SetPoint, Options+, or other proprietary binaries.

## Related open-source projects (inspiration / reference — not vendored)

| Project | License | Relationship |
|---------|---------|----------------|
| [Solaar](https://github.com/pwr-Solaar/Solaar) | GPL-2.0-or-later | Behavioural reference for feature IDs / battery; **no Solaar source copied** |
| [libratbag](https://github.com/libratbag/libratbag) | MIT | HID++ backend documentation as context |
| [OpenLogi](https://openlogi.org/) docs | Project docs | Feature descriptions (e.g. battery `0x1000`) |
| Linux `hid-logitech-hidpp` | GPL-2.0 | Interoperability reference only — not copied |
| Community Spaces / System Events notes | Various | Empirical notes; no private framework source copied |

If you modify this project by **copying GPL code** (e.g. from Solaar), you must comply with that license. The current MIT tree avoids that with an independent Swift implementation.

## Trademarks

“Logitech”, “Unifying”, “T650”, “macOS”, “Mission Control”, and “Launchpad” are trademarks of their respective owners. Used here only for interoperability identification. **Hidex** is an independent product name (see `Docs/BRAND.md`).

## macOS private / undocumented behaviour

Switching Spaces via System Events relies on OS behaviour Apple does not fully document. This app links only **public** frameworks (`Cocoa`, `IOKit`, `SwiftUI`, `ApplicationServices`).
