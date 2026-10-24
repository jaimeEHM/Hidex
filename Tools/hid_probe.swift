import Foundation
import IOKit
import IOKit.hid

let matching = IOServiceMatching(kIOHIDDeviceKey)! as NSMutableDictionary
matching[kIOHIDVendorIDKey] = 0x046D

var iterator: io_iterator_t = 0
let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
guard kr == KERN_SUCCESS else {
    fputs("IOServiceGetMatchingServices failed: \(kr)\n", stderr)
    exit(1)
}
defer { IOObjectRelease(iterator) }

var count = 0
var service = IOIteratorNext(iterator)
while service != 0 {
    if let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let maxIn = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
        let hidpp = page >= 0xFF00 && maxIn >= 19
        print(String(
            format: "%@ pid=0x%04X page=0x%04X usage=0x%02X maxIn=%d hidpp=%@",
            name, pid, page, usage, maxIn, hidpp ? "YES" : "no"
        ))
        count += 1
    }
    IOObjectRelease(service)
    service = IOIteratorNext(iterator)
}
print("Total Logitech HID interfaces: \(count)")
if count == 0 {
    print("No Unifying/Logitech receiver found. Plug it in and retry.")
    exit(2)
}
