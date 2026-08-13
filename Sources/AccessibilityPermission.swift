import ApplicationServices
import AppKit

/// État de la permission Accessibilité, sans laquelle aucun événement
/// souris synthétique ne peut être émis.
protocol PermissionChecking {
    var isGranted: Bool { get }
    /// Déclenche la demande système (une popup, une seule fois par app).
    func requestAccess()
    /// Ouvre directement le bon panneau des Réglages Système.
    func openSettings()
}

struct AccessibilityPermission: PermissionChecking {
    var isGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccess() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
