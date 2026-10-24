import AppKit
import ApplicationServices
import SwiftUI

/// Live multitouch + injection tester. Separates detection (touchpad) from injection (Spaces/MC).
final class GestureLabModel: ObservableObject {
    static let shared = GestureLabModel()

    struct FingerDot: Identifiable, Equatable {
        let id: UInt8
        let nx: CGFloat
        let ny: CGFloat
    }

    enum ClassifiedKind: String {
        case none = "—"
        case spaceLeft = "LATERAL ←  (Space izquierda)"
        case spaceRight = "LATERAL →  (Space derecha)"
        case mcUp = "VERTICAL ↑  (Mission Control)"
        case mcDown = "VERTICAL ↓  (cerrar MC)"
        case other = "Otro gesto"
    }

    @Published var fingers: Int = 0
    @Published var peak: Int = 0
    @Published var mode: String = "idle"
    @Published var accumX: Int = 0
    @Published var accumY: Int = 0
    @Published var threshold: Int = 80
    @Published var dots: [FingerDot] = []
    @Published var lastKind: ClassifiedKind = .none
    @Published var lastSwipeDetail: String = "Desliza 3 dedos ←→ o ↑↓"
    @Published var lateralCount: Int = 0
    @Published var verticalCount: Int = 0
    @Published var eventLog: [String] = []
    @Published var axTrusted: Bool = false
    @Published var injectResult: String = "—"
    /// Default OFF so swipes actually try to switch Spaces while testing.
    @Published var pauseInjection: Bool = false
    @Published var flashToken: Int = 0

    private var lastUIUpdate = Date.distantPast

    func refreshPermissions() {
        axTrusted = AXIsProcessTrusted()
    }

    func pushFrame(
        fingers: Int,
        peak: Int,
        mode: String,
        accum: CGSize,
        threshold: CGFloat,
        dots: [FingerDot]
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastUIUpdate) >= 0.033 else {
            self.fingers = fingers
            self.peak = peak
            return
        }
        lastUIUpdate = now
        DispatchQueue.main.async {
            self.fingers = fingers
            self.peak = peak
            self.mode = mode
            self.accumX = Int(accum.width)
            self.accumY = Int(accum.height)
            self.threshold = Int(threshold)
            self.dots = dots
        }
    }

    func noteSwipe(fingers: Int, ax: Int, ay: Int, action: String) {
        let kind = Self.classify(action: action, ax: ax, ay: ay)
        let line = "DETECTADO \(kind.rawValue)  |  \(fingers)F ax=\(ax) ay=\(ay)"
        DispatchQueue.main.async {
            self.lastKind = kind
            self.lastSwipeDetail = line
            self.flashToken &+= 1
            switch kind {
            case .spaceLeft, .spaceRight: self.lateralCount += 1
            case .mcUp, .mcDown: self.verticalCount += 1
            default: break
            }
            self.prependLog(line)
        }
    }

    private static func classify(action: String, ax: Int, ay: Int) -> ClassifiedKind {
        if action.contains("Space →") { return .spaceRight }
        if action.contains("Space ←") { return .spaceLeft }
        if action.localizedCaseInsensitiveContains("mission") { return .mcUp }
        if action.localizedCaseInsensitiveContains("cerrar")
            || action.localizedCaseInsensitiveContains("dismiss") {
            return .mcDown
        }
        if ax > ay { return action.contains("→") ? .spaceRight : .spaceLeft }
        return .other
    }

    func prependLog(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date()).suffix(8)
        eventLog.insert("\(stamp) \(line)", at: 0)
        if eventLog.count > 50 { eventLog = Array(eventLog.prefix(50)) }
    }

    func testSpaceLeft() { runInject("Space ←") { SpaceSwitcher.move(.left) } }
    func testSpaceRight() { runInject("Space →") { SpaceSwitcher.move(.right) } }
    func testMissionControl() {
        runInject("MC open") {
            InputInjector.perform(.missionControl)
            return true
        }
    }
    func testDismiss() {
        runInject("MC dismiss") {
            InputInjector.perform(.dismiss)
            return true
        }
    }

    private func runInject(_ label: String, _ body: () -> Bool) {
        refreshPermissions()
        let ok = body()
        let detail: String
        if label.hasPrefix("Space") {
            switch SpaceSwitcher.lastFailure {
            case .none: detail = ok ? "OK — deberías ver el cambio de escritorio" : "FAIL"
            case .accessibilityRequired: detail = "FAIL — Accesibilidad (1002). Activa T650Gestures en Ajustes."
            case .automationDenied: detail = "FAIL — Automatización System Events (-1743)"
            case .other(let s): detail = "FAIL — \(s)"
            }
        } else {
            detail = ok ? "enviado (MC no necesita Accesibilidad)" : "FAIL"
        }
        let line = "TEST \(label): \(detail) | AX=\(axTrusted)"
        injectResult = line
        prependLog(line)
        AppLog.log("GestureLab \(line)")
    }
}

struct GestureLabView: View {
    @ObservedObject var model: GestureLabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            detectionBanner

            HStack(alignment: .top, spacing: 16) {
                leftColumn
                rightColumn
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { model.refreshPermissions() }
    }

    private var detectionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Último gesto clasificado")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.lastKind.rawValue)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(bannerColor)
                .id(model.flashToken)
            Text(model.lastSwipeDetail)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Label("Laterales: \(model.lateralCount)", systemImage: "arrow.left.arrow.right")
                Label("Verticales: \(model.verticalCount)", systemImage: "arrow.up.arrow.down")
            }
            .font(.callout)
            Text("Los laterales YA se detectan. Si el escritorio no cambia, es inyección (Accesibilidad), no el gesto.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bannerColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var bannerColor: Color {
        switch model.lastKind {
        case .spaceLeft, .spaceRight: return .blue
        case .mcUp, .mcDown: return .purple
        case .other: return .orange
        case .none: return .secondary
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Touchpad en vivo").font(.headline)
            padCanvas
                .frame(width: 320, height: 240)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Dedos").foregroundStyle(.secondary)
                    Text("\(model.fingers) (peak \(model.peak))").monospacedDigit()
                }
                GridRow {
                    Text("Modo").foregroundStyle(.secondary)
                    Text(model.mode)
                }
                GridRow {
                    Text("Acumulado").foregroundStyle(.secondary)
                    Text("x=\(model.accumX) y=\(model.accumY)  umbral=\(model.threshold)")
                        .monospacedDigit()
                }
            }
            .font(.system(.body, design: .monospaced))

            Toggle(isOn: $model.pauseInjection) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pausar inyección (solo ver detección)")
                    Text(model.pauseInjection
                         ? "ON: verás LATERAL ←→ arriba pero NO cambiará el Space"
                         : "OFF: intentará cambiar Spaces al detectar lateral")
                        .font(.caption2)
                        .foregroundStyle(model.pauseInjection ? .orange : .secondary)
                }
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Probar inyección (sin gesture)").font(.headline)

            HStack {
                Circle()
                    .fill(model.axTrusted ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(model.axTrusted
                     ? "Accesibilidad OK para este binario"
                     : "Falta Accesibilidad efectiva → Spaces fallarán con 1002")
                .font(.callout)
            }

            Text(model.injectResult)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Space ←") { model.testSpaceLeft() }
                Button("Space →") { model.testSpaceRight() }
            }
            HStack {
                Button("MC ↑") { model.testMissionControl() }
                Button("MC ↓") { model.testDismiss() }
            }
            HStack {
                Button("Refrescar AX") { model.refreshPermissions() }
                Button("Abrir Accesibilidad") { InputInjector.requestAccessibilityFromMenu() }
            }

            Text("Solo DETECTADO (sin RAW)")
                .font(.headline)
                .padding(.top, 4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.eventLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(line.contains("LATERAL") ? Color.blue : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 160)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(minWidth: 320)
    }

    private var padCanvas: some View {
        GeometryReader { geo in
            ZStack {
                Path { p in
                    let cx = geo.size.width / 2
                    let cy = geo.size.height / 2
                    p.move(to: CGPoint(x: cx, y: 0)); p.addLine(to: CGPoint(x: cx, y: geo.size.height))
                    p.move(to: CGPoint(x: 0, y: cy)); p.addLine(to: CGPoint(x: geo.size.width, y: cy))
                }
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)

                Text("← lateral →\n↑ vertical ↓")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.5))
                    .multilineTextAlignment(.center)

                ForEach(model.dots) { d in
                    Circle()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .overlay(Text("\(d.id)").font(.caption2).foregroundStyle(.white))
                        .position(
                            x: d.nx * geo.size.width,
                            y: (1 - d.ny) * geo.size.height
                        )
                }

                Path { p in
                    let cx = geo.size.width / 2
                    let cy = geo.size.height / 2
                    let scale: CGFloat = 0.35
                    p.move(to: CGPoint(x: cx, y: cy))
                    p.addLine(to: CGPoint(
                        x: cx + CGFloat(model.accumX) * scale,
                        y: cy - CGFloat(model.accumY) * scale
                    ))
                }
                .stroke(Color.orange, lineWidth: 2)
            }
        }
    }
}

final class GestureLabWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        GestureLabModel.shared.refreshPermissions()
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = GestureLabView(model: .shared)
        let hosting = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Gesture Lab — T650"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 800, height: 560))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window = win
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: win
        )
    }

    @objc private func windowWillClose(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
