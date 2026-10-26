import Foundation
import CoreGraphics

/// Classifies multitouch frames into pointer / scroll / pinch / swipes and injects input.
final class GestureEngine {
    var config = GestureConfig.load()
    let tracker = TouchTracker()
    /// Con modo dual HID, el sistema ya mueve el cursor/scroll; solo inyectamos gestos 3+.
    var deferPointerToNative = true
    /// When true (Gesture Lab), classify/log swipes but skip InputInjector.perform.
    var pauseInjection = false

    private enum Mode {
        case idle
        case pointer
        case twoFinger
        case swiping

        var label: String {
            switch self {
            case .idle: return "idle"
            case .pointer: return "pointer"
            case .twoFinger: return "twoFinger"
            case .swiping: return "swiping"
            }
        }
    }

    private var mode: Mode = .idle
    private var touchStartTime = Date()
    private var accumulated = CGSize.zero
    private var swipeFired = false
    private var pinchStartDistance: CGFloat?
    private var pinchFired = false
    private var physicalButtonWasDown = false
    private var lastFingerCount = 0
    /// Peak fingers during the current contact (so 1→2→3 still counts as 3-finger swipe).
    private var peakFingerCount = 0
    private var sessionMaxMove: CGFloat = 0
    /// Centroid at gesture start — displacement from here is a better tap-vs-drag signal
    /// than summing noisy per-frame deltas.
    private var startCentroid: CGPoint?
    private var inContact = false

    func applyInfo(_ info: TouchPadRawInfo) {
        if info.xSize > 0 { tracker.xSize = CGFloat(info.xSize) }
        if info.ySize > 0 { tracker.ySize = CGFloat(info.ySize) }
        tracker.flipY = info.flipY
    }

    func reloadConfig() {
        config = GestureConfig.load()
        AppLog.log("Config reloaded")
    }

    func handle(frame: TouchPadRawFrame) {
        pauseInjection = GestureLabModel.shared.pauseInjection
        tracker.update(with: frame)
        let count = tracker.fingerCount

        handlePhysicalButton(frame: frame, fingerCount: max(count, peakFingerCount))

        if count == 0 {
            publishLab()
            // Only finish once per contact — EOF spam would reset peak and kill tap logic.
            if inContact {
                finishGesture()
            }
            return
        }

        peakFingerCount = max(peakFingerCount, count)

        if count != lastFingerCount {
            beginGesture(fingerCount: count, peak: peakFingerCount)
        }

        if startCentroid == nil, let c = currentCentroid() {
            startCentroid = c
        }
        if let start = startCentroid, let now = currentCentroid() {
            let d = hypot(now.x - start.x, now.y - start.y)
            sessionMaxMove = max(sessionMaxMove, d)
        }

        let delta = tracker.averageDelta()
        // Clamp runaway deltas (bad frames / first sample after parse bugs).
        let safeDelta = CGSize(
            width: max(-80, min(80, delta.width)),
            height: max(-80, min(80, delta.height))
        )
        accumulated.width += safeDelta.width
        accumulated.height += safeDelta.height

        // Promote to swipe mode if peak reached 3+ mid-gesture (e.g. landed as 2 then 3rd).
        if peakFingerCount >= 3 && mode != .swiping {
            mode = .swiping
            accumulated = .zero
            swipeFired = false
            AppLog.log("Gesture → swiping (peak=\(peakFingerCount))")
        }

        publishLab()

        switch mode {
        case .idle:
            break

        case .pointer:
            guard !deferPointerToNative else { break }
            let speed = config.pointerSpeed
            InputInjector.movePointer(dx: safeDelta.width * speed, dy: safeDelta.height * speed)

        case .twoFinger:
            if !pinchFired, let start = pinchStartDistance, let now = tracker.pinchDistance() {
                let diff = now - start
                if abs(diff) > config.pinchThreshold {
                    pinchFired = true
                    InputInjector.perform(diff > 0 ? .zoomIn : .zoomOut)
                    return
                }
            }
            guard !deferPointerToNative else { break }
            var sx = safeDelta.width * config.scrollSpeed * 4
            var sy = safeDelta.height * config.scrollSpeed * 4
            if config.invertScroll {
                sy = -sy
                sx = -sx
            }
            InputInjector.scroll(dx: sx, dy: sy)

        case .swiping:
            guard !swipeFired else { return }
            let ax = abs(accumulated.width)
            let ay = abs(accumulated.height)
            let threshold = config.swipeThreshold
            guard max(ax, ay) >= threshold else { return }
            swipeFired = true

            // Classify by fingers present when the swipe fires — not peak alone.
            // A brief 4th-finger brush was promoting 3↑ Mission Control → 4↑ Desktop.
            let fingers: Int
            if count >= 4 {
                fingers = 4
            } else if count >= 3 {
                fingers = 3
            } else {
                fingers = max(peakFingerCount, count)
            }
            let action: GestureAction
            if ax > ay {
                // Horizontal: same Space ←/→ for 3 or 4 fingers
                action = accumulated.width < 0 ? config.threeFingerLeft : config.threeFingerRight
            } else if fingers >= 4 {
                action = accumulated.height < 0 ? config.fourFingerUp : config.fourFingerDown
            } else {
                action = accumulated.height < 0 ? config.threeFingerUp : config.threeFingerDown
            }
            let msg = "Swipe \(fingers)F ax=\(Int(ax)) ay=\(Int(ay)) → \(action.displayName)"
            AppLog.log(msg)
            GestureLabModel.shared.noteSwipe(
                fingers: fingers, ax: Int(ax), ay: Int(ay), action: action.displayName
            )
            if pauseInjection {
                AppLog.log("Injection paused (Gesture Lab) — \(action.displayName)")
            } else {
                InputInjector.perform(action)
            }
        }
    }

    private func publishLab() {
        let xs = max(tracker.xSize, 1)
        let ys = max(tracker.ySize, 1)
        let dots: [GestureLabModel.FingerDot] = tracker.activeTouches.map { t in
            GestureLabModel.FingerDot(
                id: t.id,
                nx: min(1, max(0, t.x / xs)),
                ny: min(1, max(0, t.y / ys))
            )
        }
        GestureLabModel.shared.pushFrame(
            fingers: tracker.fingerCount,
            peak: peakFingerCount,
            mode: mode.label,
            accum: accumulated,
            threshold: config.swipeThreshold,
            dots: dots
        )
    }

    private func beginGesture(fingerCount: Int, peak: Int) {
        let previousMode = mode
        // Keep swipe accumulation when climbing 2→3; reset otherwise.
        let climbingToSwipe = previousMode == .swiping || (previousMode == .twoFinger && peak >= 3)
        if !climbingToSwipe {
            touchStartTime = Date()
            accumulated = .zero
            sessionMaxMove = 0
            startCentroid = currentCentroid()
            swipeFired = false
            pinchFired = false
            pinchStartDistance = tracker.pinchDistance()
        }
        inContact = true
        lastFingerCount = fingerCount

        switch max(fingerCount, peak) {
        case 1:
            mode = .pointer
        case 2:
            mode = .twoFinger
            if pinchStartDistance == nil {
                pinchStartDistance = tracker.pinchDistance()
            }
        default:
            mode = .swiping
        }
        AppLog.log("Gesture begin count=\(fingerCount) peak=\(peak) mode=\(mode)")
    }

    private func currentCentroid() -> CGPoint? {
        let active = tracker.activeTouches
        guard !active.isEmpty else { return nil }
        let sx = active.reduce(CGFloat(0)) { $0 + $1.x }
        let sy = active.reduce(CGFloat(0)) { $0 + $1.y }
        let n = CGFloat(active.count)
        return CGPoint(x: sx / n, y: sy / n)
    }

    private func finishGesture() {
        inContact = false
        let duration = Date().timeIntervalSince(touchStartTime)
        let travel = sessionMaxMove
        // Use peak at lift; a 2→1 release still counts as two-finger tap.
        let fingers = peakFingerCount
        let isTap = duration < config.tapMaxDuration
            && travel < config.tapMaxMove
            && !swipeFired
            && !pauseInjection

        if isTap {
            if fingers == 1, config.tapToClick {
                InputInjector.click(button: .left)
                AppLog.log("Tap 1F → clic izquierdo (\(String(format: "%.0f", duration * 1000))ms move=\(Int(travel)))")
            } else if fingers == 2, config.twoFingerTap, !pinchFired {
                InputInjector.click(button: .right)
                AppLog.log("Tap 2F → clic derecho (\(String(format: "%.0f", duration * 1000))ms move=\(Int(travel)))")
            } else if fingers == 3, config.tapToClick {
                InputInjector.click(button: .center)
                AppLog.log("Tap 3F → clic medio")
            }
        } else if fingers == 1 || fingers == 2 {
            AppLog.log(
                "Tap skip \(fingers)F dur=\(String(format: "%.0f", duration * 1000))ms " +
                "move=\(Int(travel)) lim=\(Int(config.tapMaxDuration * 1000))ms/\(Int(config.tapMaxMove))" +
                (swipeFired ? " swipe" : "") + (pauseInjection ? " paused" : "")
            )
        }

        mode = .idle
        lastFingerCount = 0
        peakFingerCount = 0
        accumulated = .zero
        sessionMaxMove = 0
        startCentroid = nil
        swipeFired = false
        pinchStartDistance = nil
        pinchFired = false
        InputInjector.setLeftButton(false)
    }

    private func handlePhysicalButton(frame: TouchPadRawFrame, fingerCount: Int) {
        if deferPointerToNative { return }
        if frame.button && !physicalButtonWasDown {
            physicalButtonWasDown = true
            if fingerCount >= 3 {
                InputInjector.click(button: .center)
            } else if fingerCount >= 2 {
                InputInjector.click(button: .right)
            } else {
                InputInjector.setLeftButton(true)
            }
        } else if !frame.button && physicalButtonWasDown {
            physicalButtonWasDown = false
            InputInjector.setLeftButton(false)
        }
    }
}
