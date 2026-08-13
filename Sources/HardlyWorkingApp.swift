import SwiftUI

@main
struct HardlyWorkingApp: App {
    @StateObject private var settings: Settings
    @StateObject private var controller: PresenceController

    // Adaptateurs sans état interne : les instancier ici est sans conséquence.
    private let permission = AccessibilityPermission()
    private let loginItem = LoginItem()

    init() {
        // Une seule instance de Settings, partagée entre le contrôleur et le menu.
        // Deux instances distinctes casseraient la réactivité de l'interface.
        let sharedSettings = Settings()
        _settings = StateObject(wrappedValue: sharedSettings)
        _controller = StateObject(wrappedValue: PresenceController(
            idleMonitor: SystemIdleMonitor(),
            jiggler: MouseJiggler(),
            permission: AccessibilityPermission(),
            settings: sharedSettings
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller,
                     settings: settings,
                     permission: permission,
                     loginItem: loginItem)
        } label: {
            Image(systemName: iconName)
        }
    }

    /// L'icône reflète l'état : actif, en pause, ou problème à régler.
    private var iconName: String {
        switch controller.state {
        case .active:          return "cup.and.saucer.fill"
        case .paused:          return "cup.and.saucer"
        case .needsPermission,
             .ineffective:     return "exclamationmark.triangle.fill"
        }
    }
}
