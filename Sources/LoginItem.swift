import Foundation
import ServiceManagement

/// Contrôle l'inscription de l'app au démarrage de session.
protocol LoginItemManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}

/// S'appuie sur SMAppService : l'app apparaît dans
/// Réglages Système → Général → Ouverture, où l'utilisateur garde le contrôle.
struct LoginItem: LoginItemManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Hardly Working: login item update failed — \(error.localizedDescription)")
        }
    }
}
