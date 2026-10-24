import Foundation
import IOKit
import IOKit.hid

protocol HIDPPSessionDelegate: AnyObject {
    func hidppSession(_ session: HIDPPSession, didReceive frame: TouchPadRawFrame)
    func hidppSession(_ session: HIDPPSession, statusChanged message: String)
    func hidppSession(_ session: HIDPPSession, batteryUpdated info: BatteryInfo)
}

/// HID++ 2.0 session: Unifying → TouchPadRawXY + battery.
final class HIDPPSession {
    weak var delegate: HIDPPSessionDelegate?

    private var device: IOHIDDevice?
    private var mouseDevice: IOHIDDevice?
    private let reportBuffer: UnsafeMutablePointer<UInt8>
    private let mouseReportBuffer: UnsafeMutablePointer<UInt8>
    private var responseQueue: [HIDPPResponse] = []
    private var deviceIndex: UInt8 = 0xFF
    private var mtFeatureIndex: UInt8 = 0
    private var batteryFeatureIndex: UInt8 = 0
    private var batteryFeatureID: UInt16 = 0
    private var rawInfo = TouchPadRawInfo()
    private var shouldRun = false
    private var threadRunLoop: CFRunLoop?
    private var watchManager: IOHIDManager?
    private var watchStartTime = Date.distantPast
    private var watchDebounceTime = Date.distantPast
    private var logRawFrames = true
    private var framesLogged = 0
    private let assembler = DualXYAssembler()
    private var lastBatteryPoll = Date.distantPast
    private let batteryPollInterval: TimeInterval = 60

    var isConnected: Bool { device != nil && mtFeatureIndex != 0 }
    var touchPadInfo: TouchPadRawInfo { rawInfo }

    init() {
        reportBuffer = .allocate(capacity: 64)
        reportBuffer.initialize(repeating: 0, count: 64)
        mouseReportBuffer = .allocate(capacity: 64)
        mouseReportBuffer.initialize(repeating: 0, count: 64)
    }

    deinit {
        shouldRun = false
        reportBuffer.deinitialize(count: 64)
        reportBuffer.deallocate()
        mouseReportBuffer.deinitialize(count: 64)
        mouseReportBuffer.deallocate()
    }

    func start() {
        guard !shouldRun else { return }
        shouldRun = true
        let thread = Thread(target: self, selector: #selector(runLoop), object: nil)
        thread.qualityOfService = .userInteractive
        thread.name = "com.t650.hidpp"
        thread.start()
    }

    func stop() {
        shouldRun = false
        if let rl = threadRunLoop { CFRunLoopStop(rl) }
    }

    func forceReconnect() {
        if let rl = threadRunLoop { CFRunLoopStop(rl) }
    }

    @objc private func runLoop() {
        threadRunLoop = CFRunLoopGetCurrent()
        while shouldRun {
            do {
                try connect()
                // Dual mode (0x15): leave mouse HID to macOS for 1–2 finger move/scroll.
                // Seizing it swallows native pointer while GestureEngine has deferPointerToNative=true.
                releaseMouseSeize()
                AppLog.log("Mouse HID left to system (dual raw) — 1–2 finger nativos")
                startDeviceWatcher()
                pollBattery()
                notify("T650 conectado — multitouch raw activo")
                AppLog.log(
                    "RawXY: \(rawInfo.xSize)x\(rawInfo.ySize) contacts=\(rawInfo.maxContacts) " +
                    "flipY=\(rawInfo.flipY) res=\(rawInfo.resolution)"
                )
                while shouldRun {
                    let result = CFRunLoopRunInMode(.defaultMode, 2.0, false)
                    if Date().timeIntervalSince(lastBatteryPoll) >= batteryPollInterval {
                        pollBattery()
                    }
                    if result == .finished || result == .stopped { break }
                }
            } catch {
                notify("HID++: \(error)")
                AppLog.log("HID++ error: \(error)")
            }
            cleanup()
            if shouldRun { Thread.sleep(forTimeInterval: 1.0) }
        }
    }

    private func notify(_ msg: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.hidppSession(self, statusChanged: msg)
        }
    }

    private func notifyBattery(_ info: BatteryInfo) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.hidppSession(self, batteryUpdated: info)
        }
    }

    // MARK: - Connect

    private func connect() throws {
        let candidates = HIDLocator.findHIDPPCandidates()
        guard !candidates.isEmpty else { throw HIDPPError.noDevice }

        for candidate in candidates {
            do {
                try openDevice(candidate.device)
                try discoverDeviceIndex()
                mtFeatureIndex = try discoverFeature(HIDPPConstants.featTouchPadRawXY)
                rawInfo = try getRawInfo()
                try setRawReportState(enabled: true, enhanced: true)
                try verifyRawEnabled()
                discoverBatteryFeature()
                assembler.reset()
                return
            } catch {
                AppLog.log("Candidate failed (\(candidate.productName)): \(error)")
                closeHIDPPDevice()
                mtFeatureIndex = 0
            }
        }
        throw HIDPPError.noDevice
    }

    private func openDevice(_ dev: IOHIDDevice) throws {
        guard IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            throw HIDPPError.openFailed
        }
        device = dev
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, reportBuffer, 64, hidppInputCallback, context)
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        AppLog.log("HID++ interface opened")
    }

    private func closeHIDPPDevice() {
        if let dev = device {
            IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(dev, reportBuffer, 64, nil, nil)
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
    }

    private func seizeMouseInterface() {
        releaseMouseSeize()
        let hidLocation = device.flatMap {
            IOHIDDeviceGetProperty($0, kIOHIDLocationIDKey as CFString) as? Int
        }
        for candidate in HIDLocator.findMouseCandidates() {
            let loc = IOHIDDeviceGetProperty(candidate.device, kIOHIDLocationIDKey as CFString) as? Int
            if let hidLocation, let loc, loc != hidLocation { continue }
            let seize = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
            let kr = IOHIDDeviceOpen(candidate.device, seize)
            if kr != kIOReturnSuccess {
                AppLog.log("Seize mouse failed (0x\(String(format: "%08X", kr))) — raw exclusivo OK")
                // With raw bit0=1 the firmware stops sending standard HID mouse reports.
                continue
            }
            mouseDevice = candidate.device
            AppLog.log("Mouse interface seized (loc=\(loc ?? -1))")
            return
        }
        AppLog.log("Mouse seize skipped — relying on exclusive raw mode")
    }

    private func releaseMouseSeize() {
        if let m = mouseDevice {
            IOHIDDeviceClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
            mouseDevice = nil
        }
    }

    // MARK: - Protocol

    private func discoverDeviceIndex() throws {
        var lastError: Error = HIDPPError.noDevice
        for useShort in [false, true] {
            for idx: UInt8 in [0xFF, 1, 2, 3, 4, 5, 6] {
                deviceIndex = idx
                do {
                    if useShort {
                        _ = try sendShortRequest(featureIndex: 0x00, functionId: 0, params: [0x00, 0x01, 0x00])
                    } else {
                        _ = try sendRequest(featureIndex: 0x00, functionId: 0, params: [0x00, 0x01, 0x00])
                    }
                    AppLog.log("HID++ device index: 0x\(String(format: "%02X", idx)) short=\(useShort)")
                    return
                } catch {
                    lastError = error
                }
            }
        }
        throw lastError
    }

    private func discoverFeature(_ featureId: UInt16) throws -> UInt8 {
        let hi = UInt8((featureId >> 8) & 0xFF)
        let lo = UInt8(featureId & 0xFF)
        var lastError: Error = HIDPPError.featureNotFound
        for attempt in 0..<4 {
            do {
                let resp = try sendRequest(featureIndex: 0x00, functionId: 0, params: [hi, lo, 0x00])
                guard !resp.params.isEmpty, resp.params[0] != 0 else {
                    throw HIDPPError.featureNotFound
                }
                AppLog.log("Feature 0x\(String(format: "%04X", featureId)) → index \(resp.params[0])")
                return resp.params[0]
            } catch {
                lastError = error
                AppLog.log("getFeature attempt \(attempt + 1) failed: \(error)")
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
        throw lastError
    }

    /// Soft probe (single attempt): returns nil if feature absent.
    private func tryDiscoverFeature(_ featureId: UInt16) -> UInt8? {
        let hi = UInt8((featureId >> 8) & 0xFF)
        let lo = UInt8(featureId & 0xFF)
        do {
            let resp = try sendRequest(featureIndex: 0x00, functionId: 0, params: [hi, lo, 0x00])
            guard !resp.params.isEmpty, resp.params[0] != 0 else { return nil }
            return resp.params[0]
        } catch {
            return nil
        }
    }

    private func getRawInfo() throws -> TouchPadRawInfo {
        let resp = try sendRequest(
            featureIndex: mtFeatureIndex,
            functionId: HIDPPConstants.cmdGetTouchPadInfo,
            params: []
        )
        return RawXYParser.parseRawInfo(params: resp.params)
    }

    /// - exclusive raw: 0x05 (bit0+bit2) — HID ratón silenciado; la app mueve el cursor.
    /// - dual mode: 0x15 (bit0+bit2+bit4) — raw + gestos/tracking nativos (respaldo si falla la app).
    private func setRawReportState(enabled: Bool, enhanced: Bool, dualMode: Bool = true) throws {
        var flags: UInt8 = 0
        if enabled { flags |= 0x01 }
        if enhanced { flags |= 0x04 }
        if enabled && dualMode { flags |= 0x10 }
        _ = try sendRequest(
            featureIndex: mtFeatureIndex,
            functionId: HIDPPConstants.cmdSetRawReportState,
            params: [flags]
        )
        AppLog.log("SET_RAW function=\(HIDPPConstants.cmdSetRawReportState) flags=0x\(String(format: "%02X", flags)) dual=\(dualMode)")
    }

    private func getRawReportState() throws -> UInt8 {
        let resp = try sendRequest(
            featureIndex: mtFeatureIndex,
            functionId: HIDPPConstants.cmdGetRawReportState,
            params: []
        )
        return resp.params.first ?? 0
    }

    private func verifyRawEnabled() throws {
        let state = try getRawReportState()
        AppLog.log("RawReportState=0x\(String(format: "%02X", state)) bit0=\(state & 1)")
        guard (state & 0x01) != 0 else {
            throw HIDPPError.rawNotEnabled
        }
    }

    // MARK: - Battery

    private func discoverBatteryFeature() {
        batteryFeatureIndex = 0
        batteryFeatureID = 0
        for feat in [HIDPPConstants.featUnifiedBattery,
                     HIDPPConstants.featBatteryStatus,
                     HIDPPConstants.featBatteryVoltage] {
            if let idx = tryDiscoverFeature(feat) {
                batteryFeatureIndex = idx
                batteryFeatureID = feat
                AppLog.log("Battery feature 0x\(String(format: "%04X", feat)) index=\(idx)")
                return
            }
        }
        AppLog.log("No battery HID++ feature found")
        notifyBattery(.unknown)
    }

    private func pollBattery() {
        lastBatteryPoll = Date()
        guard batteryFeatureIndex != 0 else { return }
        do {
            let info = try readBattery()
            AppLog.log("Battery \(info.percent.map { "\($0)%" } ?? "—") charging=\(info.charging) src=\(info.source)")
            notifyBattery(info)
        } catch {
            AppLog.log("Battery poll failed: \(error)")
        }
    }

    private func readBattery() throws -> BatteryInfo {
        switch batteryFeatureID {
        case HIDPPConstants.featUnifiedBattery:
            let resp = try sendRequest(
                featureIndex: batteryFeatureIndex,
                functionId: HIDPPConstants.cmdUnifiedBatteryGetStatus,
                params: []
            )
            // Solaar/OpenLogi: byte0 = %, status in later bytes (charging flags)
            let pct = resp.params.count > 0 ? Int(resp.params[0]) : nil
            let status = resp.params.count > 2 ? resp.params[2] : 0
            let charging = (1...4).contains(status)
            let percent = (pct != nil && pct! > 0 && pct! <= 100) ? pct : nil
            return BatteryInfo(percent: percent, charging: charging, source: "0x1004")

        case HIDPPConstants.featBatteryStatus:
            let resp = try sendRequest(
                featureIndex: batteryFeatureIndex,
                functionId: HIDPPConstants.cmdGetBatteryLevelStatus,
                params: []
            )
            // Wire: [discharge_level, next_level, status]
            // While charging, level is often 0 (unknown). Without mileage, FW uses
            // coarse steps (≈25 low / 50 good / 90 full) — not a real gauge.
            let level = resp.params.count > 0 ? Int(resp.params[0]) : 0
            let next = resp.params.count > 1 ? Int(resp.params[1]) : 0
            let status = resp.params.count > 2 ? Int(resp.params[2]) : 0
            AppLog.log("Battery raw 0x1000 level=\(level) next=\(next) status=\(status)")
            // 0=discharging 1=recharging 2=almost full 3=full 4=slow recharge
            let charging = (1...4).contains(status)
            let pct: Int?
            switch status {
            case 3:
                pct = 100
            case 2:
                pct = 95
            case 1, 4:
                // Don't invent 50% while charging — that is the coarse "good" token.
                if level >= 80 && level <= 100 { pct = level }
                else if level > 0 && level < 100 && level != 25 && level != 50 { pct = level }
                else { pct = nil } // show bolt only until status → almost full/full
            case 0:
                if level >= 0 && level <= 100 { pct = level }
                else { pct = nil }
            default:
                pct = (level > 0 && level <= 100) ? level : nil
            }
            return BatteryInfo(percent: pct, charging: charging, source: "0x1000")

        case HIDPPConstants.featBatteryVoltage:
            let resp = try sendRequest(
                featureIndex: batteryFeatureIndex,
                functionId: HIDPPConstants.cmdGetBatteryVoltage,
                params: []
            )
            guard resp.params.count >= 2 else { return .unknown }
            let mv = (Int(resp.params[0]) << 8) | Int(resp.params[1])
            // Rough LiPo map ~3.5V–4.2V
            let pct = max(0, min(100, Int(Double(mv - 3500) / 7.0)))
            let flags = resp.params.count > 2 ? resp.params[2] : 0
            return BatteryInfo(percent: pct, charging: (flags & 0x80) != 0, source: "0x1001")

        default:
            return .unknown
        }
    }

    // MARK: - Send / wait

    private func sendRequest(featureIndex: UInt8, functionId: UInt8, params: [UInt8]) throws -> HIDPPResponse {
        guard let dev = device else { throw HIDPPError.noDevice }
        var buffer = [UInt8](repeating: 0, count: HIDPPConstants.longLen)
        buffer[0] = HIDPPConstants.reportLong
        buffer[1] = deviceIndex
        buffer[2] = featureIndex
        buffer[3] = (functionId << 4) | (HIDPPConstants.softwareID & 0x0F)
        for (i, p) in params.prefix(16).enumerated() { buffer[i + 4] = p }

        responseQueue.removeAll()
        let result = IOHIDDeviceSetReport(
            dev, kIOHIDReportTypeOutput, CFIndex(HIDPPConstants.reportLong),
            buffer, buffer.count
        )
        guard result == kIOReturnSuccess else { throw HIDPPError.writeFailed }
        return try waitForResponse(featureIndex: featureIndex, expectedFunction: functionId, timeout: 2.0)
    }

    private func sendShortRequest(featureIndex: UInt8, functionId: UInt8, params: [UInt8]) throws -> HIDPPResponse {
        guard let dev = device else { throw HIDPPError.noDevice }
        var buffer = [UInt8](repeating: 0, count: HIDPPConstants.shortLen)
        buffer[0] = HIDPPConstants.reportShort
        buffer[1] = deviceIndex
        buffer[2] = featureIndex
        buffer[3] = (functionId << 4) | (HIDPPConstants.softwareID & 0x0F)
        for (i, p) in params.prefix(3).enumerated() { buffer[i + 4] = p }

        responseQueue.removeAll()
        let result = IOHIDDeviceSetReport(
            dev, kIOHIDReportTypeOutput, CFIndex(HIDPPConstants.reportShort),
            buffer, buffer.count
        )
        guard result == kIOReturnSuccess else { throw HIDPPError.writeFailed }
        return try waitForResponse(featureIndex: featureIndex, expectedFunction: functionId, timeout: 2.0)
    }

    private func waitForResponse(featureIndex: UInt8, expectedFunction: UInt8, timeout: TimeInterval) throws -> HIDPPResponse {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.05, true)
            if let errIdx = responseQueue.firstIndex(where: {
                $0.deviceIndex == self.deviceIndex && $0.featureIndex == 0xFF
            }) {
                let err = responseQueue.remove(at: errIdx)
                throw HIDPPError.protocolError(err.params.count > 1 ? err.params[1] : 0)
            }
            if let okIdx = responseQueue.firstIndex(where: {
                $0.deviceIndex == self.deviceIndex &&
                $0.featureIndex == featureIndex &&
                $0.functionId == expectedFunction &&
                $0.softwareId == HIDPPConstants.softwareID
            }) {
                return responseQueue.remove(at: okIdx)
            }
        }
        throw HIDPPError.timeout
    }

    // MARK: - Input

    fileprivate func handleInputReport(reportID: UInt8, data: UnsafePointer<UInt8>, length: Int) {
        guard length >= 1 else { return }

        var bytes = [UInt8](repeating: 0, count: length)
        for i in 0..<length { bytes[i] = data[i] }

        if bytes[0] == HIDPPConstants.reportMouse || reportID == HIDPPConstants.reportMouse {
            if length >= 21 {
                let embedded = Array(bytes.dropFirst(7))
                let frame = RawXYParser.parseMouseEmbedded(embedded)
                for assembled in assembler.push(frame) { emit(assembled) }
            }
            return
        }

        var offset = 0
        if length >= 1 && (bytes[0] == 0x10 || bytes[0] == 0x11 || bytes[0] == 0x20) {
            offset = 1
        }
        let payloadLen = length - offset
        guard payloadLen >= 3 else { return }

        let devIdx = bytes[offset]
        let featIdx = bytes[offset + 1]
        let funcSw = bytes[offset + 2]
        let funcId = funcSw >> 4
        let swId = funcSw & 0x0F
        let params = Array(bytes[(offset + 3)..<length])

        if featIdx == 0x8F {
            responseQueue.append(
                HIDPPResponse(deviceIndex: devIdx, featureIndex: 0xFF,
                              functionId: funcId, softwareId: swId, params: params)
            )
            return
        }

        if devIdx == deviceIndex,
           featIdx == mtFeatureIndex,
           funcId == HIDPPConstants.eventTouchPadRawXY,
           swId != HIDPPConstants.softwareID {
            let packet = RawXYParser.parseHIDPPParams(params)
            for assembled in assembler.push(packet) {
                emit(assembled)
            }
            return
        }

        responseQueue.append(
            HIDPPResponse(deviceIndex: devIdx, featureIndex: featIdx,
                          functionId: funcId, softwareId: swId, params: params)
        )
    }

    private func emit(_ frame: TouchPadRawFrame) {
        // Cap RAW spam so GestureEngine "Swipe … → Space" lines stay readable.
        if logRawFrames {
            let edge = frame.fingerCount == 0 || frame.button
            if framesLogged < 40 || edge {
                if framesLogged < 40 { framesLogged += 1 }
                let ids = frame.fingers.map { "\($0.fingerID)@(\($0.x),\($0.y))" }.joined(separator: " ")
                AppLog.log(
                    "RAW n=\(frame.fingerCount) eof=\(frame.endOfFrame) btn=\(frame.button) " +
                    "ts=\(frame.timestamp) contacts=\(frame.fingers.count) [\(ids)]"
                )
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.hidppSession(self, didReceive: frame)
        }
    }

    // MARK: - Watcher

    private func startDeviceWatcher() {
        stopDeviceWatcher()
        watchStartTime = Date()
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [kIOHIDVendorIDKey as String: HIDPPConstants.vendorID]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, _ in
            guard let ctx else { return }
            Unmanaged<HIDPPSession>.fromOpaque(ctx).takeUnretainedValue().handleDeviceChange(added: true)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, _ in
            guard let ctx else { return }
            Unmanaged<HIDPPSession>.fromOpaque(ctx).takeUnretainedValue().handleDeviceChange(added: false)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        watchManager = mgr
    }

    fileprivate func handleDeviceChange(added: Bool) {
        let now = Date()
        guard now.timeIntervalSince(watchStartTime) > 3.0 else { return }
        guard now.timeIntervalSince(watchDebounceTime) > 2.0 else { return }
        watchDebounceTime = now
        AppLog.log("HID device \(added ? "added" : "removed") — reconnect")
        forceReconnect()
    }

    private func stopDeviceWatcher() {
        if let mgr = watchManager {
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            watchManager = nil
        }
    }

    private func cleanup() {
        if mtFeatureIndex != 0, device != nil {
            try? setRawReportState(enabled: false, enhanced: false)
        }
        releaseMouseSeize()
        closeHIDPPDevice()
        stopDeviceWatcher()
        mtFeatureIndex = 0
        batteryFeatureIndex = 0
        batteryFeatureID = 0
        assembler.reset()
        responseQueue.removeAll()
    }
}

private func hidppInputCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context else { return }
    let session = Unmanaged<HIDPPSession>.fromOpaque(context).takeUnretainedValue()
    session.handleInputReport(reportID: UInt8(truncatingIfNeeded: reportID), data: report, length: Int(reportLength))
}
