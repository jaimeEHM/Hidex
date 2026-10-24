import Foundation

/// Parses TouchPadRawXY frames from the public Logitech 0x6100 wire format.
/// Independent Swift implementation (not a copy of Linux/Solaar source).
enum RawXYParser {

    static func parseFinger(from data: [UInt8], at offset: Int) -> TouchFinger {
        guard offset + 6 < data.count else { return TouchFinger() }
        var finger = TouchFinger()
        let b0 = data[offset]
        let b1 = data[offset + 1]
        let b2 = data[offset + 2]
        let b3 = data[offset + 3]
        // Spec: top 2 bits = type/status, low 6 bits = coordinate MSB.
        // Coordinate = ((byte & 0x3F) << 8) | lsb
        finger.x = (UInt16(b0 & 0x3F) << 8) | UInt16(b1)
        finger.y = (UInt16(b2 & 0x3F) << 8) | UInt16(b3)
        finger.contactType = b0 >> 6
        // Spec: 00=released, 01=touch, 10=hover
        finger.contactStatus = ((b2 >> 6) & 0x03) == 0x01
        finger.z = data[offset + 4]
        finger.area = data[offset + 5]
        finger.fingerID = data[offset + 6] >> 4
        return finger
    }

    /// Params payload of an HID++ long EVENT_TOUCHPAD_RAW_XY (16 bytes).
    static func parseHIDPPParams(_ params: [UInt8]) -> TouchPadRawFrame {
        var raw = TouchPadRawFrame()
        guard params.count >= 16 else { return raw }

        raw.timestamp = (UInt16(params[0]) << 8) | UInt16(params[1])
        raw.endOfFrame = (params[8] & 0x01) != 0
        raw.spurious = ((params[8] >> 1) & 0x01) != 0
        raw.button = ((params[8] >> 2) & 0x01) != 0
        raw.fingerCount = params[15] & 0x0F

        var fingers: [TouchFinger] = []
        if raw.fingerCount > 0 {
            let f0 = parseFinger(from: params, at: 2)
            if f0.fingerID != 0 || f0.contactStatus {
                fingers.append(f0)
            }
            let f1 = parseFinger(from: params, at: 9)
            // Finger1 id lives in high nibble of byte 15; parseFinger already reads that.
            if f1.fingerID != 0 || f1.contactStatus {
                fingers.append(f1)
            }
        }
        raw.fingers = fingers
        return raw
    }

    /// Mouse report path: `wtp_mouse_raw_xy_event` — data starts at report offset +7.
    static func parseMouseEmbedded(_ data: [UInt8]) -> TouchPadRawFrame {
        var raw = TouchPadRawFrame()
        guard data.count >= 14 else { return raw }

        func area(at i: Int) -> UInt8 {
            let v = data[i]
            let lo = Int(v & 0x0F)
            let hi = Int(v >> 4)
            return UInt8((lo * lo + hi * hi) / 2)
        }

        let c1 = area(at: 7)
        let c2 = area(at: 13)

        raw.timestamp = UInt16(data[1])
        var fingers: [TouchFinger] = []
        if data[7] != 0 {
            fingers.append(TouchFinger(
                contactType: 0, contactStatus: true,
                x: UInt16(data[3]) | (UInt16(data[4]) << 8),
                y: UInt16(data[5]) | (UInt16(data[6]) << 8),
                z: c1, area: c1, fingerID: data[2]
            ))
        }
        if data[13] != 0 {
            fingers.append(TouchFinger(
                contactType: 0, contactStatus: true,
                x: UInt16(data[9]) | (UInt16(data[10]) << 8),
                y: UInt16(data[11]) | (UInt16(data[12]) << 8),
                z: c2, area: c2, fingerID: data[8]
            ))
        }
        raw.fingers = fingers
        raw.endOfFrame = (data[0] >> 7) == 0
        raw.button = (data[0] & 0x01) != 0
        raw.fingerCount = UInt8(fingers.count)
        return raw
    }

    static func parseRawInfo(params: [UInt8]) -> TouchPadRawInfo {
        var info = TouchPadRawInfo()
        guard params.count >= 15 else { return info }
        info.xSize = (UInt16(params[0]) << 8) | UInt16(params[1])
        info.ySize = (UInt16(params[2]) << 8) | UInt16(params[3])
        info.zRange = params[4]
        info.areaRange = params[5]
        info.maxContacts = params[7]
        info.origin = params[8]
        let resRaw = (UInt16(params[13]) << 8) | UInt16(params[14])
        info.resolution = resRaw * 2 / 51
        return info
    }
}

/// Assembles DualXY packets that share a timestamp until `end_of_frame`.
final class DualXYAssembler {
    private var pendingTimestamp: UInt16?
    private var pendingFingers: [UInt8: TouchFinger] = [:]
    private var pendingCount: UInt8 = 0
    private var pendingButton = false
    private var pendingSpurious = false

    func reset() {
        pendingTimestamp = nil
        pendingFingers.removeAll()
        pendingCount = 0
        pendingButton = false
        pendingSpurious = false
    }

    /// Returns a complete assembled frame when ready (EOF or timestamp change).
    func push(_ packet: TouchPadRawFrame) -> [TouchPadRawFrame] {
        var completed: [TouchPadRawFrame] = []

        // Empty / release packet
        if packet.fingerCount == 0 && packet.fingers.isEmpty {
            if pendingTimestamp != nil {
                completed.append(makeFrame(endOfFrame: true, fingerCount: 0, fingers: []))
                reset()
            }
            completed.append(TouchPadRawFrame(
                timestamp: packet.timestamp, fingers: [],
                spurious: false, endOfFrame: true, fingerCount: 0, button: packet.button
            ))
            return completed
        }

        if let ts = pendingTimestamp, ts != packet.timestamp {
            // New frame started without EOF on previous — flush what we have.
            completed.append(makeFrame(
                endOfFrame: true,
                fingerCount: pendingCount,
                fingers: Array(pendingFingers.values)
            ))
            reset()
        }

        if pendingTimestamp == nil {
            pendingTimestamp = packet.timestamp
        }
        pendingCount = packet.fingerCount
        pendingButton = packet.button || pendingButton
        pendingSpurious = packet.spurious || pendingSpurious

        for f in packet.fingers where f.fingerID != 0 {
            if f.contactStatus {
                pendingFingers[f.fingerID] = f
            } else {
                pendingFingers.removeValue(forKey: f.fingerID)
            }
        }

        if packet.endOfFrame || packet.fingerCount <= 2 {
            completed.append(makeFrame(
                endOfFrame: true,
                fingerCount: pendingCount,
                fingers: Array(pendingFingers.values)
            ))
            reset()
        }

        return completed
    }

    private func makeFrame(endOfFrame: Bool, fingerCount: UInt8, fingers: [TouchFinger]) -> TouchPadRawFrame {
        TouchPadRawFrame(
            timestamp: pendingTimestamp ?? 0,
            fingers: fingers.sorted { $0.fingerID < $1.fingerID },
            spurious: pendingSpurious,
            endOfFrame: endOfFrame,
            fingerCount: fingerCount,
            button: pendingButton
        )
    }
}
