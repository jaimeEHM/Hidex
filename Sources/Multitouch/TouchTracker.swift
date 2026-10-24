import Foundation
import CoreGraphics

struct TrackedTouch {
    var id: UInt8
    var x: CGFloat
    var y: CGFloat
    var prevX: CGFloat
    var prevY: CGFloat
    var area: CGFloat
    var active: Bool
}

/// Tracks contacts from assembled DualXY frames (`finger_count` is authoritative).
final class TouchTracker {
    private(set) var touches: [UInt8: TrackedTouch] = [:]
    private(set) var fingerCount: Int = 0
    private(set) var buttonDown: Bool = false
    private(set) var endOfFrame: Bool = false

    var xSize: CGFloat = 4000
    var ySize: CGFloat = 3000
    var flipY: Bool = true

    func reset() {
        touches.removeAll()
        fingerCount = 0
        buttonDown = false
    }

    func update(with frame: TouchPadRawFrame) {
        endOfFrame = frame.endOfFrame
        buttonDown = frame.button
        fingerCount = Int(frame.fingerCount)

        if frame.fingerCount == 0 {
            touches.removeAll()
            return
        }

        var seen = Set<UInt8>()
        for finger in frame.fingers {
            guard finger.fingerID != 0, finger.contactType == 0 else { continue }
            seen.insert(finger.fingerID)
            let nx = CGFloat(finger.x)
            var ny = CGFloat(finger.y)
            if flipY { ny = ySize - ny }

            if !finger.contactStatus {
                touches.removeValue(forKey: finger.fingerID)
                continue
            }

            if var existing = touches[finger.fingerID] {
                existing.prevX = existing.x
                existing.prevY = existing.y
                existing.x = nx
                existing.y = ny
                existing.area = CGFloat(finger.area)
                existing.active = true
                touches[finger.fingerID] = existing
            } else {
                touches[finger.fingerID] = TrackedTouch(
                    id: finger.fingerID, x: nx, y: ny,
                    prevX: nx, prevY: ny,
                    area: CGFloat(finger.area), active: true
                )
            }
        }

        // Assembled EOF frames include all contacts for the timestamp —
        // drop IDs that disappeared.
        if frame.endOfFrame {
            for id in touches.keys where !seen.contains(id) {
                touches.removeValue(forKey: id)
            }
        }
    }

    var activeTouches: [TrackedTouch] {
        touches.values.filter(\.active).sorted { $0.id < $1.id }
    }

    func averageDelta() -> CGSize {
        let active = activeTouches
        guard !active.isEmpty else { return .zero }
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        for t in active {
            dx += t.x - t.prevX
            dy += t.y - t.prevY
        }
        let n = CGFloat(active.count)
        return CGSize(width: dx / n, height: dy / n)
    }

    func pinchDistance() -> CGFloat? {
        let active = activeTouches
        guard active.count >= 2 else { return nil }
        let a = active[0], b = active[1]
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}
