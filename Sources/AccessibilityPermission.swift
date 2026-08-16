import AppKit
import ApplicationServices

protocol PermissionChecking {
    var isGranted: Bool { get }
    func requestAccess()
    func openSettings()
}

/// Without this permission macOS refuses to deliver any synthetic mouse event.
struct AccessibilityPermission: PermissionChecking {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system prompt, which macOS shows only once per app.
    func requestAccess() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    func openSettings() {
        guard let settingsURL = Self.settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }
}
