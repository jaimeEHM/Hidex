# Legal notes for public distribution (not legal advice)

This document summarizes a **community-oriented review** of whether publishing this project on GitHub is generally consistent with common open-source practice. **It is not legal advice.** If you need certainty (especially commercial distribution), consult a lawyer familiar with software and reverse-engineering law in your jurisdiction.

## What this project is

- A **user-space** macOS menu-bar app written in Swift.
- Speaks the **HID++** protocol over a Logitech Unifying receiver to enable multitouch raw reports from the **T650** touchpad.
- Emulates macOS gestures (Mission Control, Spaces, taps, etc.) using public APIs (`CGEvent`, `NSAppleScript` / System Events, `NSWorkspace`).

## What this project is not

- Not a kernel extension / DriverKit driver.
- Not a redistributed copy of Logitech Options, Options+, SetPoint, or firmware.
- Not a fork of Solaar, libratbag, or other GPL/MIT projects (no vendored third-party source trees).

## Protocol / reverse engineering

1. **Public docs:** Logitech publishes HID++ 2.0 materials ([cpg-docs](https://github.com/Logitech/cpg-docs)) and the community hosts feature PDFs (including TouchPadRawXY `0x6100`). Implementing a client from documentation is the normal path used by Solaar, libratbag, and similar tools.
2. **Logitech EULA:** Logitech’s consumer [Software Licence Agreement](https://www.logitech.com/en-us/tos/software-license-agreement) restricts reverse-engineering of *their Software* (Options / Options+ / companion apps). Independently writing an interoperable client from **public specs** is a different activity from decompiling those products. Still, do **not** ship Logitech binaries or extracted proprietary assets.
3. **Clean-room style:** Wire formats live in `Docs/PROTOCOL.md`; Swift sources are original. Avoid pasting large GPL sources (Solaar, Linux `hid-logitech-hidpp.c`) into an MIT repo without relicensing correctly.
4. **Facts vs code:** Protocol constants and bit layouts are not copyrightable as such in many jurisdictions; **copying GPL source text** would be. This tree keeps an independent implementation.

## Choosing MIT for *this* codebase

MIT fits an independent implementation and makes reuse easy for the community.  

**Caution:** If future contributions paste substantial **GPL-2.0** code (e.g. from Solaar), the combined work may need to be distributed under GPL. Keep attributions in `NOTICE.md` and review PRs carefully.

## Apple / App Store

- The app uses Accessibility and Automation permissions — expected for gesture injection.
- Notarization / Developer ID is **optional** for GitHub releases; without it, Gatekeeper may warn (“unidentified developer”). Document “Open Anyway” for users.
- App Store distribution is likely unsuitable (IOKit HID++ device access, Automation of System Events, non-sandboxed design).

## Publishing checklist

- [x] `LICENSE` (MIT) for original code  
- [x] `NOTICE.md` credits for docs and related projects  
- [x] README states non-affiliation with Logitech/Apple  
- [x] No Logitech proprietary binaries in the repo  
- [ ] Optional: Apple Developer ID + notarize release DMG/PKG for smoother installs  

## Conclusion (practical)

Publishing this repository publicly under MIT, with clear attribution to protocol documentation and related open-source projects, aligns with how the Linux HID++ community has operated for years. Respect trademarks, do not ship Logitech’s apps/firmware, and keep third-party license boundaries clean.
