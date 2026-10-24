import Foundation

enum HIDPPConstants {
    static let vendorID = 0x046D
    static let reportShort: UInt8 = 0x10
    static let reportLong: UInt8 = 0x11
    static let reportMouse: UInt8 = 0x02
    static let shortLen = 7
    static let longLen = 20
    static let softwareID: UInt8 = 0x0A

    static let featRoot: UInt16 = 0x0000
    static let featFeatureSet: UInt16 = 0x0001
    static let featTouchPadRawXY: UInt16 = 0x6100
    static let featBatteryStatus: UInt16 = 0x1000
    static let featBatteryVoltage: UInt16 = 0x1001
    static let featUnifiedBattery: UInt16 = 0x1004

    /// Logitech DJ / Unifying wireless product ID for T650.
    static let t650WPID: UInt16 = 0x4101

    // 0x6100 function numbers (spec). Wire byte = (fn << 4) | softwareID.
    // NEVER use Linux pre-shifted values like 0x20 with another << 4.
    static let cmdGetTouchPadInfo: UInt8 = 0
    static let cmdGetRawReportState: UInt8 = 1
    static let cmdSetRawReportState: UInt8 = 2
    static let eventTouchPadRawXY: UInt8 = 0

    // Battery function numbers
    static let cmdGetBatteryLevelStatus: UInt8 = 0   // 0x1000
    static let cmdGetBatteryVoltage: UInt8 = 0       // 0x1001
    static let cmdUnifiedBatteryGetStatus: UInt8 = 1 // 0x1004

    static let originLowerLeft: UInt8 = 0x01
    static let originUpperLeft: UInt8 = 0x03
}

enum HIDPPError: Error, CustomStringConvertible {
    case noDevice
    case openFailed
    case writeFailed
    case timeout
    case featureNotFound
    case protocolError(UInt8)
    case notConnected
    case rawNotEnabled

    var description: String {
        switch self {
        case .noDevice: return "No se encontró receptor Unifying / interfaz HID++"
        case .openFailed: return "No se pudo abrir el dispositivo HID"
        case .writeFailed: return "Fallo al enviar reporte HID++"
        case .timeout: return "Timeout esperando respuesta HID++"
        case .featureNotFound: return "Feature HID++ unavailable (is the touchpad off?)"
        case .protocolError(let c): return "Error de protocolo HID++ 0x\(String(format: "%02X", c))"
        case .notConnected: return "Sesión HID++ no conectada"
        case .rawNotEnabled: return "Raw multitouch no quedó activo (bit0=0)"
        }
    }
}

struct HIDPPResponse {
    let deviceIndex: UInt8
    let featureIndex: UInt8
    let functionId: UInt8
    let softwareId: UInt8
    let params: [UInt8]
}

struct TouchPadRawInfo {
    var xSize: UInt16 = 0
    var ySize: UInt16 = 0
    var zRange: UInt8 = 0
    var areaRange: UInt8 = 0
    var maxContacts: UInt8 = 0
    var origin: UInt8 = 0
    var resolution: UInt16 = 0

    var flipY: Bool { origin == HIDPPConstants.originLowerLeft }
}

struct TouchFinger: Equatable {
    var contactType: UInt8 = 0
    var contactStatus: Bool = false
    var x: UInt16 = 0
    var y: UInt16 = 0
    var z: UInt8 = 0
    var area: UInt8 = 0
    var fingerID: UInt8 = 0
}

struct TouchPadRawFrame {
    var timestamp: UInt16 = 0
    /// Up to 2 slots per HID++ packet; assembled frames may have more.
    var fingers: [TouchFinger] = []
    var spurious: Bool = false
    var endOfFrame: Bool = false
    var fingerCount: UInt8 = 0
    var button: Bool = false
}

struct BatteryInfo: Equatable {
    var percent: Int?
    var charging: Bool
    var source: String

    static let unknown = BatteryInfo(percent: nil, charging: false, source: "none")
}

enum AppLog {
    static let fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".hidex.log")

    private static let lock = NSLock()
    private static let iso = ISO8601DateFormatter()

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func log(_ msg: String) {
        let line = "\(iso.string(from: Date())) \(msg)\n"
        fputs(line, stderr)
        guard let data = line.data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: data)
            return
        }
        if let fh = try? FileHandle(forWritingTo: fileURL) {
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            fh.write(data)
        }
    }
}
