# Checklist Spaces + Mission Control

Tras `./install.sh` (firma **T650Gestures Local**, no ad hoc):

## Una sola vez — Accesibilidad efectiva

1. Ajustes → Privacidad y seguridad → Accesibilidad.
2. Quita entradas viejas de T650Gestures (build/ o ad hoc).
3. **+** → `/Applications/T650Gestures.app` → activar.
4. Menú de la app → **Reiniciar app**.
5. Menú → **Diagnosticar Spaces…** → debe decir `AXIsProcessTrusted=true`.
6. Si pide Automatización → System Events, aceptar.

## Mission Control (no debe romperse)

- [ ] 3 dedos ↑ → abre Mission Control (`Inject MC OPEN` en log).
- [ ] Con MC abierto, 3 dedos ↓ → cierra (`Inject MC CLOSE`).
- [ ] Con MC abierto, 3 dedos ↑ → no cierra (`MC already open — ignore ↑`).

## Spaces

- [ ] 3 dedos ← → cambia escritorio (`SpaceSwitcher System Events ← OK`).
- [ ] 3 dedos → → cambia escritorio (`… → OK`).
- [ ] Diez swipes laterales seguidos → **cero** diálogos de Accesibilidad.

## Hotkeys del sistema

Ya verificados en esta máquina: symbolic hotkeys **79/81** enabled.
Si Spaces no cambian con AX=true: Teclado → Atajos → Mission Control → Mover izquierda/derecha un espacio.

## Phase 2 (Dock swipe IOHID)

No implementada: solo si System Events falla **con** `AXIsProcessTrusted=true`.
Camino primario en macOS 27 = System Events ⌃←/→.
