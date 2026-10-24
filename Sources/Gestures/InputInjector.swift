import AppKit
import ApplicationServices
import CoreGraphics

/// System gesture injection.
/// - Mission Control open/close: toggle via Mission Control.app (no Automation) — do not change lightly.
/// - Spaces: System Events via SpaceSwitcher (no Automation pre-check; no per-swipe prompts).
enum InputInjector {

    private static var leftDown = false
    private static var missionControlOpen = false
    /// One-shot soft notice for Spaces permission issues (no Settings spam).
    private static var didNoteSpacesPermission = false

    private static let keyLeft: CGKeyCode = 0x7B
    private static let keyRight: CGKeyCode = 0x7C
    private static let keyDown: CGKeyCode = 0x7D
    private static let keyEscape: CGKeyCode = 0x35
    private static let keyControl: CGKeyCode = 0x3B
    private static let keyCommand: CGKeyCode = 0x37
    private static let keyShift: CGKeyCode = 0x38
    private static let keyOption: CGKeyCode = 0x3A
    private static let keyF11: CGKeyCode = 0x67

    private static let missionControlURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app")

    // MARK: - Pointer

    static func movePointer(dx: CGFloat, dy: CGFloat) {
        let cdx = max(-120, min(120, dx))
        let cdy = max(-120, min(120, dy))
        guard abs(cdx) > 0.01 || abs(cdy) > 0.01 else { return }
        let loc = NSEvent.mouseLocation
        guard let screen = NSScreen.main else { return }
        let cgPoint = CGPoint(x: loc.x + cdx, y: (screen.frame.height - loc.y) + cdy)
        let type: CGEventType = leftDown ? .leftMouseDragged : .mouseMoved
        if let move = CGEvent(mouseEventSource: nil, mouseType: type,
                              mouseCursorPosition: cgPoint, mouseButton: .left) {
            move.post(tap: .cghidEventTap)
        }
    }

    static func setLeftButton(_ down: Bool) {
        guard down != leftDown else { return }
        leftDown = down
        let loc = cgMouseLocation()
        let type: CGEventType = down ? .leftMouseDown : .leftMouseUp
        if let e = CGEvent(mouseEventSource: nil, mouseType: type,
                           mouseCursorPosition: loc, mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
    }

    static func click(button: CGMouseButton = .left) {
        let loc = cgMouseLocation()
        let downType: CGEventType = button == .left ? .leftMouseDown :
            (button == .right ? .rightMouseDown : .otherMouseDown)
        let upType: CGEventType = button == .left ? .leftMouseUp :
            (button == .right ? .rightMouseUp : .otherMouseUp)
        if let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                              mouseCursorPosition: loc, mouseButton: button) {
            if button == .center { down.setIntegerValueField(.mouseEventButtonNumber, value: 2) }
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(mouseEventSource: nil, mouseType: upType,
                            mouseCursorPosition: loc, mouseButton: button) {
            if button == .center { up.setIntegerValueField(.mouseEventButtonNumber, value: 2) }
            up.post(tap: .cghidEventTap)
        }
    }

    static func scroll(dx: CGFloat, dy: CGFloat) {
        let wheelY = Int32(dy.rounded())
        let wheelX = Int32(dx.rounded())
        guard wheelY != 0 || wheelX != 0 else { return }
        if let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                           wheelCount: 2, wheel1: wheelY, wheel2: wheelX, wheel3: 0) {
            e.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Mission Control (preserved behavior)

    private static func openMissionControlApp() {
        guard FileManager.default.fileExists(atPath: missionControlURL.path) else { return }
        NSWorkspace.shared.openApplication(at: missionControlURL, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Permissions (on-demand only)

    /// Query Automation without treating −600 (System Events not running) as denial.
    @discardableResult
    static func ensureAutomationPermission(prompt: Bool = false) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc, typeWildCard, typeWildCard, prompt
        )
        // -600 procNotFound: System Events idle — not a refusal.
        let ok = (status == OSStatus(noErr) || status == -600)
        AppLog.log("Automation System Events status=\(status) ok=\(ok) prompt=\(prompt)")
        if status == -1743 && prompt {
            openAutomationSettings()
        }
        return ok
    }

    static func openAutomationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Automation"
        ]
        for s in urls {
            if let u = URL(string: s) {
                NSWorkspace.shared.open(u)
                return
            }
        }
    }

    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for s in urls {
            if let u = URL(string: s) {
                NSWorkspace.shared.open(u)
                return
            }
        }
    }

    /// Menu-only: request AX prompt once and open Settings.
    static func requestAccessibilityFromMenu() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openAccessibilitySettings()
    }

    static func relaunchApp() {
        let path = Bundle.main.bundlePath
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? proc.run()
        NSApp.terminate(nil)
    }

    private static func noteSpacesFailureOnce() {
        guard !didNoteSpacesPermission else { return }
        didNoteSpacesPermission = true
        switch SpaceSwitcher.lastFailure {
        case .accessibilityRequired:
            AppLog.log(
                "Spaces: Accesibilidad efectiva ausente (AXIsProcessTrusted=" +
                "\(AXIsProcessTrusted())). Menú → Diagnosticar Spaces…"
            )
        case .automationDenied:
            AppLog.log("Spaces: Automatización denegada para System Events. Menú → Permitir Automatización…")
        case .other(let s):
            AppLog.log("Spaces: fallo \(s)")
        case .none:
            break
        }
    }

    // MARK: - System Events helpers (non-Spaces actions)

    @discardableResult
    private static func systemEventsKey(_ code: Int, control: Bool) -> Bool {
        let using = control ? " using control down" : ""
        let source = """
        tell application "System Events"
          key code \(code)\(using)
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        _ = script.executeAndReturnError(&error)
        if let error {
            let num = error[NSAppleScript.errorNumber] as? Int ?? -1
            let msg = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            AppLog.log("System Events key \(code) err=\(num) \(msg.prefix(120))")
            return false
        }
        return true
    }

    private static func postShortcut(key: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        var mods: [(CGKeyCode, CGEventFlags)] = []
        if flags.contains(.maskControl) { mods.append((keyControl, .maskControl)) }
        if flags.contains(.maskCommand) { mods.append((keyCommand, .maskCommand)) }
        if flags.contains(.maskShift) { mods.append((keyShift, .maskShift)) }
        if flags.contains(.maskAlternate) { mods.append((keyOption, .maskAlternate)) }
        var downFlags: CGEventFlags = []
        for (modKey, modFlag) in mods {
            downFlags.insert(modFlag)
            if let e = CGEvent(keyboardEventSource: src, virtualKey: modKey, keyDown: true) {
                e.flags = downFlags
                e.post(tap: .cghidEventTap)
            }
        }
        if let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
        for (modKey, _) in mods.reversed() {
            if let e = CGEvent(keyboardEventSource: src, virtualKey: modKey, keyDown: false) {
                e.flags = []
                e.post(tap: .cghidEventTap)
            }
        }
    }

    static func perform(_ action: GestureAction) {
        DispatchQueue.main.async {
            switch action {
            case .none:
                break

            case .missionControl:
                // PRESERVE: only OPEN; re-open while open would close.
                if missionControlOpen {
                    AppLog.log("MC already open — ignore ↑ (use ↓ to close)")
                    return
                }
                openMissionControlApp()
                missionControlOpen = true
                AppLog.log("Inject MC OPEN")

            case .dismiss:
                // PRESERVE: close via Mission Control.app toggle when we opened it.
                if missionControlOpen {
                    openMissionControlApp()
                    missionControlOpen = false
                    AppLog.log("Inject MC CLOSE (toggle .app)")
                } else if systemEventsKey(53, control: false) {
                    AppLog.log("Inject dismiss Esc (System Events)")
                } else {
                    postShortcut(key: keyEscape, flags: [])
                    AppLog.log("Inject dismiss Esc (CGEvent)")
                }

            case .appExpose:
                if systemEventsKey(125, control: true) {
                    AppLog.log("Inject App Exposé OK")
                } else {
                    postShortcut(key: keyDown, flags: .maskControl)
                }

            case .desktop:
                // Show Desktop = F11 (key 103), not Ctrl+F11.
                if systemEventsKey(103, control: false) {
                    AppLog.log("Inject Desktop OK (F11)")
                } else {
                    postShortcut(key: keyF11, flags: [])
                    AppLog.log("Inject Desktop CGEvent F11")
                }

            case .spaceLeft:
                if SpaceSwitcher.move(.left) {
                    AppLog.log("Inject Space ← OK")
                } else {
                    noteSpacesFailureOnce()
                    AppLog.log("Inject Space ← FAILED")
                }

            case .spaceRight:
                if SpaceSwitcher.move(.right) {
                    AppLog.log("Inject Space → OK")
                } else {
                    noteSpacesFailureOnce()
                    AppLog.log("Inject Space → FAILED")
                }

            case .launchpad:
                openLaunchpad()

            case .notificationCenter:
                _ = systemEventsKey(160, control: false)

            case .zoomIn:
                postShortcut(key: 0x18, flags: .maskCommand)

            case .zoomOut:
                postShortcut(key: 0x1B, flags: .maskCommand)

            case .lookup:
                postShortcut(key: 0x02, flags: [.maskControl, .maskCommand])
            }
        }
    }

    /// Launchpad.app was removed on some macOS 27 installs — try paths, Dock, then App Exposé.
    private static func openLaunchpad() {
        let candidates = [
            "/System/Applications/Launchpad.app",
            "/Applications/Launchpad.app",
            "/System/Library/CoreServices/LaunchPad.app"
        ]
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                AppLog.log("Inject Launchpad via \(path)")
                return
            }
        }
        // Dock UI element (name localized — try Spanish + English)
        let dockScript = """
        tell application "System Events"
          tell process "Dock"
            set frontmost to true
            try
              click UI element "Launchpad" of list 1
              return "en"
            end try
            try
              click UI element "Launchpad" of list 1 of UI element 1
              return "en2"
            end try
          end tell
        end tell
        return "miss"
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: dockScript) {
            let result = script.executeAndReturnError(&error)
            if error == nil, let s = result.stringValue, s != "miss" {
                AppLog.log("Inject Launchpad via Dock (\(s))")
                return
            }
        }
        // Fallback: App Exposé (Control+Down) — useful 4-finger-down stand-in
        if systemEventsKey(125, control: true) {
            AppLog.log("Inject Launchpad fallback → App Exposé (Launchpad.app ausente)")
        } else {
            postShortcut(key: keyDown, flags: .maskControl)
            AppLog.log("Inject Launchpad fallback → App Exposé CGEvent")
        }
    }

    private static func cgMouseLocation() -> CGPoint {
        let loc = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) })
                ?? NSScreen.main else {
            return CGPoint(x: loc.x, y: loc.y)
        }
        return CGPoint(x: loc.x, y: screen.frame.maxY - loc.y)
    }
}
