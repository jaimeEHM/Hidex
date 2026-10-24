import Foundation
import IOKit
import IOKit.hid

/// Locates Logitech vendor HID interfaces. Prefer registry walk because
/// IOHIDManager often fails to enumerate Unifying on macOS Sequoia/arm64.
enum HIDLocator {

    struct Candidate {
        let device: IOHIDDevice
        let productName: String
        let productID: Int
        let usagePage: Int
        let usage: Int
        let maxInput: Int
        let isMouseInterface: Bool
    }

    static func findHIDPPCandidates() -> [Candidate] {
        enumerateLogitechDevices().filter { c in
            c.usagePage >= 0xFF00 && c.maxInput >= 19
        }
    }

    /// Mouse / pointer interfaces on the Unifying receiver (to seize and avoid double cursor).
    static func findMouseCandidates() -> [Candidate] {
        enumerateLogitechDevices().filter { $0.isMouseInterface }
    }

    static func enumerateLogitechDevices() -> [Candidate] {
        var results: [Candidate] = []
        var seen = Set<String>()

        let matching = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
        matching[kIOHIDVendorIDKey] = HIDPPConstants.vendorID

        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        if kr == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let device = IOHIDDeviceCreate(kCFAllocatorDefault, service),
                   let c = candidate(from: device) {
                    let key = "\(c.productID)-\(c.usagePage)-\(c.usage)-\(c.maxInput)"
                    if seen.insert(key).inserted {
                        results.append(c)
                    }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
        }

        if results.isEmpty {
            let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let match: [String: Any] = [kIOHIDVendorIDKey as String: HIDPPConstants.vendorID]
            IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
            if IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
                if let set = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> {
                    for dev in set {
                        if let c = candidate(from: dev) {
                            results.append(c)
                        }
                    }
                }
                IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            }
        }

        for c in results {
            AppLog.log(
                "HID: \(c.productName) pid=0x\(String(format: "%04X", c.productID)) " +
                "page=0x\(String(format: "%04X", c.usagePage)) usage=0x\(String(format: "%02X", c.usage)) " +
                "maxIn=\(c.maxInput) mouse=\(c.isMouseInterface)"
            )
        }
        return results
    }

    private static func candidate(from device: IOHIDDevice) -> Candidate? {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let maxIn = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
        // Unifying: keyboard usage 0x06, mouse usage 0x02 on desktop page 0x01.
        let isMouse = (page == 0x01 && usage == 0x02)
        return Candidate(
            device: device,
            productName: name,
            productID: pid,
            usagePage: page,
            usage: usage,
            maxInput: maxIn,
            isMouseInterface: isMouse
        )
    }
}
