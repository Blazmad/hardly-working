import SwiftUI

@main
struct HardlyWorkingApp: App {
    @StateObject private var settings: Settings
    @StateObject private var controller: PresenceController

    private let permission = AccessibilityPermission()
    private let loginItem = LoginItem()

    init() {
        let settings = Settings()
        let controller = PresenceController.monitoring(settings)
        _settings = StateObject(wrappedValue: settings)
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller,
                     settings: settings,
                     permission: permission,
                     loginItem: loginItem)
        } label: {
            Image(systemName: statusIconName)
                .startingMonitoringWhenRendered(controller)
        }
    }

    private var statusIconName: String {
        switch controller.state {
        case .active:
            "cup.and.saucer.fill"
        case .paused:
            "cup.and.saucer"
        case .needsPermission, .ineffective:
            "exclamationmark.triangle.fill"
        }
    }
}

private extension PresenceController {
    /// Starts the loop on the freshly built instance. Inside `App.init()` the
    /// `@StateObject` accessors are not installed by SwiftUI yet and must not be
    /// read, so the caller cannot start monitoring through them.
    static func monitoring(_ settings: Settings) -> PresenceController {
        let controller = PresenceController(idleMonitor: SystemIdleMonitor(),
                                            jiggler: MouseJiggler(),
                                            permission: AccessibilityPermission(),
                                            settings: settings)
        controller.refresh()
        return controller
    }
}

private extension View {
    /// SwiftUI renders a `MenuBarExtra` label as soon as the app launches, but
    /// builds its menu content only when the menu is opened. Monitoring has to
    /// start from the label: hung off the content, the app would do nothing until
    /// the user clicked its icon, while its whole purpose is to work while they
    /// are away from the machine.
    func startingMonitoringWhenRendered(_ controller: PresenceController) -> some View {
        onAppear { controller.refresh() }
    }
}
