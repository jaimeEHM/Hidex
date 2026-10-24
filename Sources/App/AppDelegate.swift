import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, HIDPPSessionDelegate {
    private var statusItem: NSStatusItem!
    private var accessibilityTimer: Timer?
    private let session = HIDPPSession()
    private let engine = GestureEngine()
    private let preferences = PreferencesWindowController()
    private let gestureLab = GestureLabWindowController()
    private var statusTitle = "Buscando T650…"
    private var enabled = true
    private var battery = BatteryInfo.unknown

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.reset()
        AppLog.log("T650Gestures launched")
        session.delegate = self
        setupMenuBar()
        enableLoginItemOnFirstLaunch()
        ensureAccessibilityAndStart()

        NotificationCenter.default.addObserver(
            forName: .t650ConfigDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.engine.reloadConfig()
            self?.rebuildMenu()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(onSystemWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.log("Terminating — disable raw mode")
        session.stop()
        // Give HID thread a moment to send SET_RAW off.
        Thread.sleep(forTimeInterval: 0.35)
    }

    // MARK: - HIDPPSessionDelegate

    func hidppSession(_ session: HIDPPSession, didReceive frame: TouchPadRawFrame) {
        guard enabled else { return }
        engine.applyInfo(session.touchPadInfo)
        engine.handle(frame: frame)
    }

    func hidppSession(_ session: HIDPPSession, statusChanged message: String) {
        statusTitle = message
        AppLog.log(message)
        updateStatusItemAppearance()
        rebuildMenu()
    }

    func hidppSession(_ session: HIDPPSession, batteryUpdated info: BatteryInfo) {
        battery = info
        updateStatusItemAppearance()
        rebuildMenu()
    }

    // MARK: - Lifecycle

    @objc private func onSystemWake() {
        AppLog.log("Wake — reconnect in 2s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.session.forceReconnect()
        }
    }

    private func ensureAccessibilityAndStart() {
        // Dual-mode raw: 1–2 finger native; 3+ via this app. No Settings prompts on launch.
        enabled = true
        engine.deferPointerToNative = true
        session.start()
        updateStatusItemAppearance()
        rebuildMenu()

        let ax = AXIsProcessTrusted()
        AppLog.log(
            "Accessibility trusted=\(ax) — Spaces ←→ need AX+Automation; " +
            "MC ↑/↓ uses Mission Control.app (no AX)"
        )
        if ax {
            statusTitle = "Gestos activos"
            updateStatusItemAppearance()
        } else {
            // TCC was reset / grant missing for this Local-signed binary.
            // One prompt + open Settings (required for Spaces; MC already works).
            statusTitle = "Activa Accesibilidad → Spaces"
            updateStatusItemAppearance()
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                InputInjector.openAccessibilitySettings()
            }
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
                guard let self else { return }
                if AXIsProcessTrusted() {
                    AppLog.log("Accessibility trusted=true — Spaces listos")
                    timer.invalidate()
                    self.statusTitle = "Gestos activos"
                    self.updateStatusItemAppearance()
                    self.rebuildMenu()
                }
            }
        }
    }

    // MARK: - Menu / battery icon

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemAppearance()
        rebuildMenu()
    }

    private func updateStatusItemAppearance() {
        guard let btn = statusItem?.button else { return }
        btn.image = batterySymbolImage()
        btn.imagePosition = .imageLeft
        if let pct = battery.percent {
            btn.title = " \(pct)%"
        } else if battery.charging {
            btn.title = " …" // charging, exact % unknown (HID++ coarse status)
        } else {
            btn.title = " —"
        }
        btn.toolTip = statusTitle
    }

    private func batterySymbolImage() -> NSImage? {
        let name: String
        if battery.charging {
            name = "battery.100.bolt"
        } else {
            switch battery.percent ?? -1 {
            case 90...100: name = "battery.100"
            case 65..<90: name = "battery.75"
            case 40..<65: name = "battery.50"
            case 15..<40: name = "battery.25"
            case 0..<15: name = "battery.0"
            default: name = "rectangle.and.hand.point.up.left.filled"
            }
        }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "T650 battery")
        img?.isTemplate = true
        return img
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let cfg = engine.config

        let title = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let batLabel: String
        if let pct = battery.percent {
            batLabel = battery.charging ? "Batería \(pct)% (cargando)" : "Batería \(pct)%"
        } else if battery.charging {
            batLabel = "Batería cargando…"
        } else {
            batLabel = "Batería desconocida"
        }
        let batItem = NSMenuItem(title: batLabel, action: nil, keyEquivalent: "")
        batItem.isEnabled = false
        menu.addItem(batItem)
        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Preferencias…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let toggle = NSMenuItem(
            title: enabled ? "Pausar gestos" : "Reanudar gestos",
            action: #selector(toggleEnabled(_:)), keyEquivalent: "p"
        )
        toggle.target = self
        menu.addItem(toggle)

        let reconnect = NSMenuItem(title: "Reconectar HID++", action: #selector(reconnect(_:)), keyEquivalent: "r")
        reconnect.target = self
        menu.addItem(reconnect)

        menu.addItem(.separator())

        let gestures = NSMenuItem(title: "Gestos actuales", action: nil, keyEquivalent: "")
        gestures.isEnabled = false
        menu.addItem(gestures)
        menu.addItem(infoItem("3↑  \(cfg.threeFingerUp.displayName)"))
        menu.addItem(infoItem("3↓  \(cfg.threeFingerDown.displayName)"))
        menu.addItem(infoItem("3/4←→ \(cfg.threeFingerLeft.displayName) / \(cfg.threeFingerRight.displayName)"))
        menu.addItem(infoItem("4↑  \(cfg.fourFingerUp.displayName)"))
        menu.addItem(infoItem("4↓  \(cfg.fourFingerDown.displayName)"))
        menu.addItem(infoItem("2 dedos  Scroll nativo"))

        menu.addItem(.separator())

        let labItem = NSMenuItem(
            title: "Gesture Lab (gestos en vivo)…",
            action: #selector(openGestureLab(_:)), keyEquivalent: "g"
        )
        labItem.target = self
        menu.addItem(labItem)

        let diagItem = NSMenuItem(
            title: "Diagnosticar Spaces…",
            action: #selector(diagnoseSpaces(_:)), keyEquivalent: ""
        )
        diagItem.target = self
        menu.addItem(diagItem)

        let axItem = NSMenuItem(
            title: AXIsProcessTrusted() ? "Accesibilidad ✓" : "Activar Accesibilidad (Spaces)…",
            action: #selector(requestAccessibility(_:)), keyEquivalent: ""
        )
        axItem.target = self
        menu.addItem(axItem)

        let autoItem = NSMenuItem(
            title: "Permitir Automatización (System Events)…",
            action: #selector(requestAutomation(_:)), keyEquivalent: ""
        )
        autoItem.target = self
        menu.addItem(autoItem)

        let relaunchItem = NSMenuItem(
            title: "Reiniciar app",
            action: #selector(relaunch(_:)), keyEquivalent: ""
        )
        relaunchItem.target = self
        menu.addItem(relaunchItem)

        let logItem = NSMenuItem(title: "Abrir log", action: #selector(openLog(_:)), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        let login = NSMenuItem(title: "Iniciar al encender", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = UserDefaults.standard.bool(forKey: "startAtLogin") ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: "  " + title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func openPreferences(_ sender: Any?) {
        preferences.show()
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        enabled.toggle()
        rebuildMenu()
    }

    @objc private func reconnect(_ sender: NSMenuItem) {
        statusTitle = "Reconectando…"
        updateStatusItemAppearance()
        rebuildMenu()
        session.forceReconnect()
    }

    @objc private func openLog(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(AppLog.fileURL)
    }

    @objc private func openGestureLab(_ sender: NSMenuItem) {
        gestureLab.show()
    }

    @objc private func diagnoseSpaces(_ sender: NSMenuItem) {
        let text = SpaceSwitcher.diagnose()
        let alert = NSAlert()
        alert.messageText = "Diagnóstico Spaces"
        alert.informativeText = text + "\n\nPrueba también 3 dedos ←→ y revisa ~/.t650gestures.log"
        alert.addButton(withTitle: "OK")
        if !AXIsProcessTrusted() {
            alert.addButton(withTitle: "Abrir Accesibilidad")
        }
        if alert.runModal() == .alertSecondButtonReturn {
            InputInjector.requestAccessibilityFromMenu()
        }
    }

    @objc private func requestAccessibility(_ sender: NSMenuItem) {
        InputInjector.requestAccessibilityFromMenu()
    }

    @objc private func relaunch(_ sender: NSMenuItem) {
        InputInjector.relaunchApp()
    }

    @objc private func requestAutomation(_ sender: NSMenuItem) {
        // prompt:true may show TCC; do not treat −600 as failure inside ensureAutomationPermission.
        _ = InputInjector.ensureAutomationPermission(prompt: true)
        // Trigger a real System Events call so TCC can appear if needed.
        _ = SpaceSwitcher.move(.right)
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let on = sender.state != .on
        sender.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: "startAtLogin")
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            AppLog.log("SMAppService: \(error)")
        }
    }

    private func enableLoginItemOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: "didFirstLaunch") else { return }
        UserDefaults.standard.set(true, forKey: "didFirstLaunch")
        UserDefaults.standard.set(true, forKey: "startAtLogin")
        try? SMAppService.mainApp.register()
    }
}
