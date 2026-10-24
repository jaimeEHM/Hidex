# T650 Gestures

**Driver en espacio de usuario** para el Logitech Wireless Rechargeable Touchpad **T650** en macOS (Apple Silicon e Intel).

Habla **HID++ 2.0** con el receptor Unifying, activa multitouch raw (`TouchPadRawXY` `0x6100`) y traduce gestos a acciones de macOS: Mission Control, Spaces, Escritorio, taps, etc.

> **No afiliado a Logitech ni a Apple.** Proyecto comunitario independiente. Ver [NOTICE.md](NOTICE.md) y [LEGAL.md](LEGAL.md).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue.svg)](#requisitos)
[![Universal](https://img.shields.io/badge/binary-arm64%20%7C%20x86__64-success.svg)](#compilar)

---

## ¿Por qué existe?

El T650 funciona en Mac como ratón básico, pero **macOS no expone gestos multitouch** del pad Logitech como en un Magic Trackpad. En Linux, el kernel / Solaar / libratbag documentan HID++ raw XY. Esta app trae esa idea a macOS **sin kext**: solo IOKit + inyección de gestos.

## Características

| Gesto | Acción por defecto |
|--------|---------------------|
| 1 dedo mover | Puntero nativo (modo dual HID++) |
| Toque 1 dedo | Clic izquierdo *(configurable)* |
| 2 dedos | Scroll nativo |
| Toque 2 dedos | Clic derecho *(configurable)* |
| 3 dedos ↑ | Mission Control (abrir) |
| 3 dedos ↓ | Cerrar Mission Control |
| 3 / 4 dedos ←→ | Cambiar Spaces (escritorios) |
| 4 dedos ↑ | Mostrar Escritorio (F11) |
| 4 dedos ↓ | Launchpad o App Exposé (si no hay Launchpad.app) |
| Clic físico | Botón del pad (HID nativo) |

Extras:

- Icono de menú con **batería** aproximada (HID++ `0x1000`)
- **Preferencias** (velocidades, taps, mapeo de gestos 3/4 dedos)
- **Gesture Lab** — visualiza dedos y prueba inyección (Spaces / MC)
- Inicio al encender (opcional)

## Requisitos

- macOS **13** o posterior (probado en macOS 27 / Apple Silicon)
- Touchpad **T650** + receptor **Unifying** (WPID dispositivo `0x4101`, receptor típico `0xC52B`)
- Permisos:
  1. **Accesibilidad** → `T650Gestures` (obligatorio para Spaces y taps inyectados)
  2. **Automatización** → `T650Gestures` → **System Events** (Spaces vía ⌃←/→)
  3. Atajos de teclado → Mission Control → *Mover a la izquierda/derecha un espacio* activos

## Instalación (usuario)

### Opción A — DMG / PKG (release)

1. Descarga `T650Gestures-*-universal.dmg` o `.pkg` desde [Releases](../../releases).
2. Arrastra la app a **Aplicaciones** (DMG) o ejecuta el PKG.
3. Abre la app. Si Gatekeeper avisa: *Privacidad y seguridad → Abrir de todas formas* (el binario de GitHub no está notarizado con Developer ID de Apple salvo que un maintainer lo firme).
4. Concede **Accesibilidad** y **Automatización → System Events**.
5. Menú de la batería → **Reiniciar app** tras conceder permisos.

### Opción B — Desde el código

```bash
git clone https://github.com/jaimeEHM/T650Gestures.git
cd T650Gestures
./install.sh                  # arm64 rápido → /Applications
# o instalador universal:
./scripts/package-installer.sh
```

`install.sh` firma con una identidad local **T650Gestures Local** cuando es posible, para que Accesibilidad sobreviva a rebuilds (evita firma ad hoc que cambia el cdhash).

## Compilar

```bash
# Solo arquitectura nativa (más rápido)
./build.sh

# Universal arm64 + x86_64 + DMG + PKG → dist/
./scripts/package-installer.sh
```

Artefactos en `dist/`:

- `T650Gestures-VERSION-universal.dmg`
- `T650Gestures-VERSION-universal.pkg`
- `SHA256SUMS.txt`

## Uso diario

1. Enchufa el Unifying y enciende el T650.
2. Arranca **T650 Gestures** (icono de batería en la barra de menú).
3. Ajusta toques y gestos en **Preferencias…**
4. Si Spaces fallan: menú → **Diagnosticar Spaces…** / **Gesture Lab**.
5. Log: `~/.t650gestures.log`

## Cómo funciona (arquitectura)

```text
Unifying (USB) ──HID++──► HIDPPSession ──frames──► DualXYAssembler
                                                      │
                                                      ▼
                                               TouchTracker
                                                      │
                                                      ▼
                                               GestureEngine
                                 ┌────────────────────┼────────────────────┐
                                 ▼                    ▼                    ▼
                          Native HID mouse      InputInjector        SpaceSwitcher
                          (1–2 dedos dual)   (MC.app, taps, …)   (System Events ⌃←/→)
```

- **Modo dual raw** (`SET_RAW` flags `0x15`): multitouch HID++ **y** movimiento/scroll nativos.
- **Mission Control** se abre/cierra con `Mission Control.app` (no requiere Automatización).
- **Spaces** usan System Events (`key code 123/124 using control down`); los `CGEvent` sintéticos de Ctrl+flecha los ignora WindowServer en macOS reciente.

Detalle del protocolo: [Docs/PROTOCOL.md](Docs/PROTOCOL.md).

## Licencia y comunidad

- Código propio: **[MIT](LICENSE)** — Copyright © 2026 Jaime EHM ([@jaimeEHM](https://github.com/jaimeEHM))
- Atribuciones y relación con otros proyectos: **[NOTICE.md](NOTICE.md)**
- Notas para publicar / no afiliación: **[LEGAL.md](LEGAL.md)**

### Proyectos y documentación a respetar / citar

Gracias a la comunidad que documentó HID++ y gestos en macOS:

- [Solaar](https://github.com/pwr-Solaar/Solaar) (GPL-2.0+) — referencia de comportamiento HID++ en Linux  
- [libratbag](https://github.com/libratbag/libratbag) (MIT)  
- Documentación TouchPadRawXY / HID++ (colección [lekensteyn](https://lekensteyn.nl/logitech.html), docs CPG HID++ 2.0)  
- Experiencia comunitaria sobre Spaces + System Events en macOS moderno  

Este repositorio **no copia** el código fuente de Solaar; reimplementa el cliente en Swift a partir de especificaciones y observación.

## Limitaciones

- No aparece como Magic Trackpad nativo (no hay driver Kernel/DriverKit).
- Launchpad.app puede no existir en macOS muy recientes → fallback a App Exposé.
- Batería HID++ `0x1000` es a veces un nivel grueso (p. ej. “good” ≈ 50 %), no un gauge fino.
- Sin notarización Apple, Gatekeeper mostrará advertencias en máquinas ajenas.
- APIs de Spaces no son públicas; el enfoque System Events puede cambiar en futuros macOS.

## Contribuir

Issues y PRs bienvenidos: dispositivos Unifying distintos, mejoras de gestos, localización, CI de build universal.

1. Fork → rama → PR  
2. No incluir binarios de Logitech ni secretos de firma Apple  
3. Mantener `NOTICE.md` al reutilizar documentación de terceros  

## Autor

**Jaime EHM** — [@jaimeEHM](https://github.com/jaimeEHM)

Hecho como aporte a quien sigue usando el T650 en Mac y quiere gestos de verdad.
