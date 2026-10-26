import AppKit

/// Menu-bar icon: touchpad silhouette + optional charge cue (bar / bolt).
/// Numeric battery % lives only in the menu, not beside the icon.
enum StatusItemIcon {
    static func image(percent: Int?, charging: Bool, size: CGFloat = 16) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let pad = NSBezierPath(
                roundedRect: NSRect(x: 1.5, y: 3.5, width: 13, height: 10),
                xRadius: 2.2,
                yRadius: 2.2
            )
            pad.lineWidth = 1.4
            NSColor.black.setStroke()
            pad.stroke()

            // Finger contact hints (multitouch cue)
            let dots: [(CGFloat, CGFloat)] = [(5, 8.5), (8, 7.2), (11, 8.5)]
            for (x, y) in dots {
                let d = NSBezierPath(ovalIn: NSRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2))
                NSColor.black.setFill()
                d.fill()
            }

            // Thin battery level bar inside the pad
            let level: CGFloat
            if let pct = percent {
                level = max(0.08, min(1, CGFloat(pct) / 100))
            } else if charging {
                level = 0.55
            } else {
                level = 0.2
            }
            let barMax: CGFloat = 9
            let bar = NSBezierPath(
                roundedRect: NSRect(x: 3.5, y: 4.6, width: barMax * level, height: 1.4),
                xRadius: 0.6,
                yRadius: 0.6
            )
            NSColor.black.setFill()
            bar.fill()

            if charging {
                // Small bolt tip at top-right of pad
                let bolt = NSBezierPath()
                bolt.move(to: NSPoint(x: 12.2, y: 12.2))
                bolt.line(to: NSPoint(x: 10.8, y: 10.4))
                bolt.line(to: NSPoint(x: 11.6, y: 10.4))
                bolt.line(to: NSPoint(x: 10.4, y: 8.6))
                bolt.line(to: NSPoint(x: 12.0, y: 10.6))
                bolt.line(to: NSPoint(x: 11.2, y: 10.6))
                bolt.close()
                NSColor.black.setFill()
                bolt.fill()
            }

            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = L10n.t(
            "Hidex — touchpad y batería",
            "Hidex — touchpad and battery"
        )
        return img
    }
}
