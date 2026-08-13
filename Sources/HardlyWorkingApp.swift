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
        let sharedController = PresenceController(
            idleMonitor: SystemIdleMonitor(),
            jiggler: MouseJiggler(),
            permission: AccessibilityPermission(),
            settings: sharedSettings
        )
        _settings = StateObject(wrappedValue: sharedSettings)
        _controller = StateObject(wrappedValue: sharedController)

        // Démarrage immédiat, sur la référence locale (jamais via l'accesseur de
        // @StateObject, qui n'est pas encore installé par SwiftUI à ce stade).
        sharedController.refresh()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller,
                     settings: settings,
                     permission: permission,
                     loginItem: loginItem)
        } label: {
            Image(systemName: iconName)
                // ⚠️ Démarrage de la surveillance : il DOIT être déclenché ici, sur
                // l'icône, et non depuis le menu. SwiftUI ne construit le contenu d'un
                // MenuBarExtra qu'à l'ouverture du menu — accrocher le démarrage au menu
                // donnerait une app qui ne surveille rien tant que l'utilisateur n'a pas
                // cliqué sur l'icône. Or tout l'intérêt du produit est de fonctionner
                // pendant qu'il est LOIN de sa machine. L'icône, elle, est rendue dès le
                // lancement.
                .onAppear { controller.refresh() }
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
