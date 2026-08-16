import Foundation
import ServiceManagement

protocol LoginItemManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}

/// Registers through `SMAppService`, so the app shows up in System Settings →
/// General → Login Items, where the user keeps control of it.
struct LoginItem: LoginItemManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        } catch {
            NSLog("Hardly Working: login item update failed — \(error.localizedDescription)")
        }
    }
}
