# Brand research — Hidex

**Decision:** product name **Hidex** (from **HID++** + expressive *ex*).  
**Not** affiliated with Logitech, Apple, or third-party gesture apps.

## Why rename away from “T650 Gestures”

| Concern | Notes |
|---------|--------|
| Trademark | “Logitech”, “T650”, “Unifying” belong to Logitech. Using the model as the *product* name risks confusion and trademark claims. |
| Descriptiveness | The app is a user-space HID++ gesture bridge; the model is a *compatible device*, not the brand. |
| Community | An original name makes forks, releases, and citations clearer. |

## Names considered and rejected

| Candidate | Reason rejected |
|-----------|-----------------|
| T650 Gestures | Embeds Logitech model in product name |
| Padbridge / PADbridge | Existing broadcast trademark (PAD::bridge™) |
| TouchBridge | Existing macOS gesture product |
| Glidepad | Existing browser touchpad extension |
| Fingerflow | Collides with fingerprint ML / hobby apps |
| Zesture | Existing proprietary webcam-gesture product (zesture.app) |

## Chosen brand

- **Name:** Hidex  
- **Pronunciation:** “high-dex”  
- **Tagline (ES):** Gestos multitouch para touchpads inalámbricos HID++ en macOS  
- **Tagline (EN):** Multitouch gestures for wireless HID++ touchpads on macOS  
- **Bundle ID:** `com.jimmks7.hidex`  
- **App bundle:** `Hidex.app`  
- **Compatible hardware (documentation only):** Logitech Wireless Rechargeable Touchpad **T650** + Unifying receiver (WPID `0x4101`)  
- **Trademark stance:** “Logitech”, “T650”, “Unifying”, “macOS”, “Mission Control” appear only as interoperability references (see `NOTICE.md`).

## License note on language

The **MIT license legal text** remains in **English** (canonical MIT template). Spanish UI/docs are first-class; when the OS language is not English, the app and docs default to **Spanish**, then English.
