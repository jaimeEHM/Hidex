# Protocolo HID++ — TouchPadRawXY `0x6100` (perfil documentado: T650)

Implementación independiente en Swift (**Hidex**) basada en la [spec Logitech 0x6100](https://lekensteyn.nl/files/logitech/6100_touchpadraw.pdf) y el comportamiento documentado por la comunidad Linux (WPID `0x4101`). No se incluye código fuente de Solaar/libratbag.

> El nombre del producto es **Hidex**. “T650” / “Logitech” solo identifican hardware compatible.

## Framing

| Tipo | Report ID | Tamaño |
|------|-----------|--------|
| Short | `0x10` | 7 bytes |
| Long  | `0x11` | 20 bytes |

Cuerpo tras el report ID:

```text
[deviceIndex, featureIndex, (functionID << 4) | softwareID, params…]
```

`functionID` es el **número de función** (0, 1, 2…), no el valor pre-shift de Linux.

### Pitfall crítico

Linux define `CMD_TOUCHPAD_SET_RAW_REPORT_STATE = 0x20` (= fn 2 ya desplazado) y hace `0x20 | softwareID` **sin** otro `<< 4`.

Si se usa `0x20` con `(fn << 4)`, el `UInt8` desborda a `0x00` y se envía **GetTouchPadInfo** en lugar de **SetRawReportState**. El multitouch raw nunca se activa.

Correcto en esta app:

| Función | Número |
|---------|--------|
| GetTouchPadInfo | 0 |
| GetRawReportState | 1 |
| SetRawReportState | 2 |

## TouchPadRawXY `0x6100`

### SetRawReportState (fn 2)

Flags:

- bit 0: enable raw (1 = solo HID++, nada en pipe HID ratón)
- bit 2: enhanced sensitivity

Valor típico: `0x05`. Tras el SET, leer GetRawReportState y exigir bit0=1.

### EVENT DualXY (fn 0, notificación)

Máximo **2 contactos por paquete**. Con 3+ dedos: varios paquetes, mismo `timestamp`, `finger_count` repetido, último con `end_of_frame`.

## Batería

Probar features en orden: `0x1004` → `0x1000` → `0x1001`.

| Feature | Función | % |
|---------|---------|---|
| 0x1000 | 0 | params[0], status params[2] |
| 0x1004 | 1 | params[0] |
| 0x1001 | 0 | voltaje → % aproximado |

## macOS gotchas

- Sequoia/arm64: preferir `IOServiceGetMatchingServices` + `IOHIDDeviceCreate`.
- Escribir solo `kIOHIDReportTypeOutput`.
- Primera respuesta RF puede tardar >0.5 s.
- HID++: usage page `0xFF00`, max input ≥ 19.
