import Foundation

/// Runtime localization. English OS → EN; otherwise Spanish (default), then EN strings as fallback pairs.
enum L10n {
    enum Lang { case es, en }

    static var lang: Lang = {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "es"
        if preferred.hasPrefix("en") { return .en }
        return .es
    }()

    static func t(_ es: String, _ en: String) -> String {
        lang == .en ? en : es
    }

    static var appName: String { "Hidex" }

    static var versionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(appName) \(short) (\(build))"
    }

    static var searchingDevice: String { t("Buscando touchpad…", "Looking for touchpad…") }
    static var gesturesActive: String { t("Gestos activos", "Gestures active") }
    static var enableAccessibility: String {
        t("Activa Accesibilidad → Spaces", "Enable Accessibility → Spaces")
    }
    static var reconnecting: String { t("Reconectando…", "Reconnecting…") }
    static var connectedRaw: String {
        t("Touchpad conectado — multitouch raw activo", "Touchpad connected — raw multitouch active")
    }

    static func batteryPercent(_ pct: Int, charging: Bool) -> String {
        if charging {
            return t("Batería \(pct)% (cargando)", "Battery \(pct)% (charging)")
        }
        return t("Batería \(pct)%", "Battery \(pct)%")
    }

    static var batteryChargingUnknown: String { t("Batería cargando…", "Battery charging…") }
    static var batteryUnknown: String { t("Batería desconocida", "Battery unknown") }

    static var preferences: String { t("Preferencias…", "Preferences…") }
    static var pauseGestures: String { t("Pausar gestos", "Pause gestures") }
    static var resumeGestures: String { t("Reanudar gestos", "Resume gestures") }
    static var reconnectHID: String { t("Reconectar HID++", "Reconnect HID++") }
    static var currentGestures: String { t("Gestos actuales", "Current gestures") }
    static var twoFingerNativeScroll: String { t("2 dedos  Scroll nativo", "2 fingers  Native scroll") }
    static var gestureLab: String { t("Gesture Lab (gestos en vivo)…", "Gesture Lab (live)…") }
    static var diagnoseSpaces: String { t("Diagnosticar Spaces…", "Diagnose Spaces…") }
    static var accessibilityOK: String { t("Accesibilidad ✓", "Accessibility ✓") }
    static var enableAccessibilityMenu: String {
        t("Activar Accesibilidad (Spaces)…", "Enable Accessibility (Spaces)…")
    }
    static var allowAutomation: String {
        t("Permitir Automatización (System Events)…", "Allow Automation (System Events)…")
    }
    static var relaunchApp: String { t("Reiniciar app", "Relaunch app") }
    static var openLog: String { t("Abrir log", "Open log") }
    static var startAtLogin: String { t("Iniciar al encender", "Launch at login") }
    static var quit: String { t("Salir", "Quit") }
    static var aboutVersion: String { t("Acerca de / versión", "About / version") }

    static var spacesDiagnosisTitle: String { t("Diagnóstico Spaces", "Spaces diagnosis") }
    static var preferencesWindowTitle: String {
        t("Preferencias — Hidex", "Preferences — Hidex")
    }
    static var gestureLabWindowTitle: String {
        t("Gesture Lab — Hidex", "Gesture Lab — Hidex")
    }

    static var ok: String { "OK" }
    static var openAccessibility: String { t("Abrir Accesibilidad", "Open Accessibility") }
}
