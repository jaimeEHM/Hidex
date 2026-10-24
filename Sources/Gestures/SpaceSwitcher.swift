import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

/// Switch Spaces via System Events ⌃←/→ (primary on macOS 27).
///
/// Do NOT use:
/// - CGEvent Ctrl+Arrow (WindowServer ignores synthetic hotkeys)
/// - CGSManagedDisplaySetCurrentSpace (bookkeeping only; no visual switch)
/// - Pre-check AEDeterminePermissionToAutomateTarget (−600 = System Events idle, not denied)
///
/// Mission Control open/close stays in InputInjector via Mission Control.app — not here.
enum SpaceSwitcher {

    enum Direction {
        case left
        case right

        var keyCode: Int { self == .left ? 123 : 124 }
        var label: String { self == .left ? "←" : "→" }
        var isRight: Bool { self == .right }
    }

    enum Failure: Equatable {
        case none
        case accessibilityRequired   // AppleScript 1002
        case automationDenied        // -1743
        case other(String)
    }

    private(set) static var lastFailure: Failure = .none
    private static var didLogHotkeys = false

    @discardableResult
    static func move(_ direction: Direction) -> Bool {
        lastFailure = .none
        logHotkeysOnce()

        if systemEventsControlArrow(direction) {
            return true
        }
        // Only try Dock swipe when AX is granted; otherwise keep accessibilityRequired.
        if AXIsProcessTrusted(), postDockSwipe(direction) {
            AppLog.log("SpaceSwitcher Dock swipe \(direction.label) posted (AX ok)")
            lastFailure = .none
            return true
        }
        return false
    }

    @discardableResult
    private static func systemEventsControlArrow(_ direction: Direction) -> Bool {
        let code = direction.keyCode
        let source = """
        tell application "System Events"
          key code \(code) using control down
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            lastFailure = .other("NSAppleScript create failed")
            AppLog.log("SpaceSwitcher \(direction.label) create failed")
            return false
        }
        _ = script.executeAndReturnError(&error)
        if let error {
            let num = error[NSAppleScript.errorNumber] as? Int ?? -1
            let msg = (error[NSAppleScript.errorMessage] as? String) ?? "\(error)"
            AppLog.log("SpaceSwitcher \(direction.label) err=\(num) \(msg.prefix(160))")
            if num == 1002 || msg.localizedCaseInsensitiveContains("keystroke")
                || msg.localizedCaseInsensitiveContains("presiones de tecla") {
                lastFailure = .accessibilityRequired
            } else if num == -1743 {
                lastFailure = .automationDenied
            } else {
                lastFailure = .other("err=\(num)")
            }
            return false
        }
        AppLog.log("SpaceSwitcher System Events \(direction.label) OK")
        lastFailure = .none
        return true
    }

    /// Pre-macOS-27 style DockControl gesture. On 27 without IOHID payload it may no-op;
    /// kept as best-effort when System Events is blocked.
    @discardableResult
    private static func postDockSwipe(_ direction: Direction) -> Bool {
        let fieldEventType = CGEventField(rawValue: 55)!
        let fieldGestureHIDType = CGEventField(rawValue: 110)!
        let fieldSwipeMotion = CGEventField(rawValue: 123)!
        let fieldSwipeProgress = CGEventField(rawValue: 124)!
        let fieldSwipeVelocityX = CGEventField(rawValue: 129)!
        let fieldSwipeVelocityY = CGEventField(rawValue: 130)!
        let fieldGesturePhase = CGEventField(rawValue: 132)!
        let fieldScrollGestureFlags = CGEventField(rawValue: 135)!
        let fieldGestureZoomDeltaX = CGEventField(rawValue: 137)!
        let fieldGestureScrollY = CGEventField(rawValue: 116)!

        let eventGesture: Int64 = 29
        let eventDockControl: Int64 = 30
        let hidDockSwipe: Int64 = 23
        let right = direction.isRight
        // Match InstantSpaceSwitcher: right → positive progress
        let progress = right ? 2.0 : -2.0
        let velocity = right ? 400.0 : -400.0
        let flagDir: Int64 = right ? 1 : 0

        guard
            let beganDock = CGEvent(source: nil),
            let beganGesture = CGEvent(source: nil),
            let endedDock = CGEvent(source: nil),
            let endedGesture = CGEvent(source: nil)
        else { return false }

        beganGesture.type = CGEventType(rawValue: 29)!
        beganGesture.setIntegerValueField(fieldEventType, value: eventGesture)

        beganDock.type = CGEventType(rawValue: 30)!
        beganDock.setIntegerValueField(fieldEventType, value: eventDockControl)
        beganDock.setIntegerValueField(fieldGestureHIDType, value: hidDockSwipe)
        beganDock.setIntegerValueField(fieldGesturePhase, value: 1) // began
        beganDock.setIntegerValueField(fieldScrollGestureFlags, value: flagDir)
        beganDock.setIntegerValueField(fieldSwipeMotion, value: 1)
        beganDock.setDoubleValueField(fieldGestureScrollY, value: 0)
        beganDock.setDoubleValueField(fieldGestureZoomDeltaX, value: Double.leastNormalMagnitude)

        endedGesture.type = CGEventType(rawValue: 29)!
        endedGesture.setIntegerValueField(fieldEventType, value: eventGesture)

        endedDock.type = CGEventType(rawValue: 30)!
        endedDock.setIntegerValueField(fieldEventType, value: eventDockControl)
        endedDock.setIntegerValueField(fieldGestureHIDType, value: hidDockSwipe)
        endedDock.setIntegerValueField(fieldGesturePhase, value: 4) // ended
        endedDock.setDoubleValueField(fieldSwipeProgress, value: progress)
        endedDock.setIntegerValueField(fieldScrollGestureFlags, value: flagDir)
        endedDock.setIntegerValueField(fieldSwipeMotion, value: 1)
        endedDock.setDoubleValueField(fieldGestureScrollY, value: 0)
        endedDock.setDoubleValueField(fieldSwipeVelocityX, value: velocity)
        endedDock.setDoubleValueField(fieldSwipeVelocityY, value: 0)
        endedDock.setDoubleValueField(fieldGestureZoomDeltaX, value: Double.leastNormalMagnitude)

        beganDock.post(tap: .cgSessionEventTap)
        beganGesture.post(tap: .cgSessionEventTap)
        usleep(12_000)
        endedDock.post(tap: .cgSessionEventTap)
        endedGesture.post(tap: .cgSessionEventTap)
        return true
    }

    /// One-shot diagnostic for the menu: AX + hotkeys + a dry permission note (no Settings UI).
    static func diagnose() -> String {
        let ax = AXIsProcessTrusted()
        let left = hotkeyEnabled(79)
        let right = hotkeyEnabled(81)
        var lines: [String] = []
        lines.append("AXIsProcessTrusted=\(ax)")
        lines.append("Hotkey 79 (Space ←) enabled=\(left.map(String.init) ?? "?")")
        lines.append("Hotkey 81 (Space →) enabled=\(right.map(String.init) ?? "?")")
        if !ax {
            lines.append("Acción: Accesibilidad → T650Gestures (/Applications), luego Reiniciar app.")
            lines.append("Si el interruptor ya está on pero AX=false: quita la entrada, + de nuevo (firma Local).")
        }
        AppLog.log("SpaceSwitcher diagnose: \(lines.joined(separator: " | "))")
        return lines.joined(separator: "\n")
    }

    private static func logHotkeysOnce() {
        guard !didLogHotkeys else { return }
        didLogHotkeys = true
        let left = hotkeyEnabled(79)
        let right = hotkeyEnabled(81)
        AppLog.log(
            "Space hotkeys 79=\(left.map { $0 ? "on" : "off" } ?? "?") " +
            "81=\(right.map { $0 ? "on" : "off" } ?? "?")"
        )
        if left == false || right == false {
            AppLog.log(
                "WARNING: enable Keyboard → Shortcuts → Mission Control → Move left/right a space"
            )
        }
    }

    private static func hotkeyEnabled(_ id: Int) -> Bool? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let keys = plist["AppleSymbolicHotKeys"] as? [String: Any],
              let entry = keys[String(id)] as? [String: Any],
              let enabled = entry["enabled"] as? Bool
        else { return nil }
        return enabled
    }
}
