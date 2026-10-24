# Legal notes for public distribution (not legal advice)

**ES:** Resumen orientativo para publicar Hidex en GitHub de forma pública. **No es asesoramiento legal.**  
**EN:** Community-oriented review of publishing Hidex publicly. **Not legal advice.**

## What this project is

- A **user-space** macOS menu-bar app (**Hidex**) written in Swift.
- Speaks **HID++** over a Logitech Unifying receiver to enable multitouch raw reports from documented compatible hardware (e.g. **T650**).
- Emulates macOS gestures using public APIs (`CGEvent`, System Events, `NSWorkspace`).

## What this project is not

- Not a kernel extension / DriverKit driver.
- Not a redistributed copy of Logitech Options, Options+, SetPoint, or firmware.
- Not a fork of Solaar, libratbag, or other GPL/MIT projects (no vendored third-party source trees).
- Not affiliated with the unrelated historical product names rejected in `Docs/BRAND.md`.

## Protocol / reverse engineering

1. **Public docs:** Logitech publishes HID++ 2.0 materials ([cpg-docs](https://github.com/Logitech/cpg-docs)); community hosts feature PDFs (`0x6100`). Same path as Solaar / libratbag.
2. **Logitech EULA:** Restricts reverse-engineering of *their Software*. An independent interoperable client from **public specs** is different from decompiling Options+. Do **not** ship Logitech binaries.
3. **Clean-room style:** Wire formats in `Docs/PROTOCOL.md`; Swift sources are original. Do not paste GPL sources into this MIT tree without relicensing.

## License language

- Canonical **MIT** legal text stays in **English** (`LICENSE`) — standard practice; required wording is the English template.
- Spanish informative translation: `LICENSE.es.md`.
- App/docs: Spanish default unless the OS preferred language is English.

## Publishing checklist

- [x] `LICENSE` (MIT, English) + `LICENSE.es.md`
- [x] `NOTICE.md` / `LEGAL.md` / `Docs/BRAND.md`
- [x] No Logitech proprietary binaries
- [x] Public repo under community-friendly terms
- [ ] Optional: Apple Developer ID + notarize (smoother Gatekeeper)

## Conclusion

Publishing **Hidex** publicly under MIT, with clear attribution and without shipping Logitech proprietary software, aligns with how the Linux HID++ community has operated for years.
