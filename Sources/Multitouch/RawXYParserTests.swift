#if DEBUG
import Foundation

/// Lightweight self-check compiled only when building with -DDEBUG.
enum RawXYParserTests {
    static func run() {
        // Finger layout from Linux hidpp_touchpad_touch_event
        // Construct params: timestamp(2) + finger0(7) + flags in byte8 overlapping + finger1 + count
        var params = [UInt8](repeating: 0, count: 16)
        // finger0 at offset 2: x≈100, y≈200, status on, id=1
        // x = (x_m << 6) | data[1]; x_m = data[0]<<2; contact in data[0]>>6
        params[2] = 0x00 // contact_type 0, x high bits
        params[3] = 100  // x low
        params[4] = 0x40 // contact_status=1 (bit6), y high
        params[5] = 200  // y low
        params[6] = 10   // z
        params[7] = 12   // area
        params[8] = 0x05 // eof=1, button=1 (bit2)
        params[9] = 0
        params[10] = 0
        params[11] = 0
        params[12] = 0
        params[13] = 0
        params[14] = 0x10 // finger_id nibble = 1
        params[15] = 0x01 // finger_count = 1
        // Fix finger0 id in params[8] area — finger0 id is params[2+6]=params[8], conflict with flags.
        // In protocol finger0 bytes are data[2..8] and flags ARE data[8]. finger_id uses data[6]>>4 of finger block = params[8]>>4.
        // So params[8] holds both flags (low bits) and finger_id high nibble for finger0.
        params[8] = 0x15 // id nibble 1, eof+button

        let frame = RawXYParser.parseHIDPPParams(params)
        assert(frame.fingerCount == 1)
        assert(frame.endOfFrame)
        assert(frame.button)
        assert(frame.fingers[0].contactStatus)
        AppLog.log("RawXYParserTests OK")
    }
}
#endif
