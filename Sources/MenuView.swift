import SwiftUI

/// Le contenu du menu déroulant de la barre de statut.
struct MenuView: View {
    @ObservedObject var controller: PresenceController
    @ObservedObject var settings: Settings

    let permission: PermissionChecking
    let loginItem: LoginItemManaging

    @State private var launchAtLogin: Bool = false

    var body: some View {
        // Bandeau d'alerte : affiché seulement quand quelque chose ne va pas.
        if controller.state == .needsPermission {
            Text("Accessibility permission required")
            Button("Open Accessibility Settings…") {
                permission.requestAccess()
                permission.openSettings()
            }
            Divider()
        } else if controller.state == .ineffective {
            Text("Mouse nudge had no effect — check Accessibility permission")
            Button("Open Accessibility Settings…") {
                permission.openSettings()
            }
            Divider()
        }

        Toggle("Active", isOn: $settings.isEnabled)

        Divider()

        Picker("Idle threshold", selection: $settings.idleThresholdSeconds) {
            ForEach(Settings.availableThresholds, id: \.self) { seconds in
                Text("\(seconds / 60) min").tag(seconds)
            }
        }

        Toggle("Launch at login", isOn: $launchAtLogin)

        Divider()

        Button("Quit Hardly Working") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        // Ces modificateurs portent sur le dernier élément du menu, mais leur effet
        // est global à la vue : ils synchronisent l'interface avec le contrôleur.
        .onAppear {
            launchAtLogin = loginItem.isEnabled
            controller.refresh()
        }
        .onChange(of: settings.isEnabled) { _, _ in
            controller.refresh()
        }
        .onChange(of: settings.idleThresholdSeconds) { _, _ in
            controller.refresh()
        }
        .onChange(of: launchAtLogin) { _, newValue in
            loginItem.setEnabled(newValue)
            // Relire l'état réel : si l'inscription a échoué, la case doit se décocher
            // au lieu de mentir à l'utilisateur.
            launchAtLogin = loginItem.isEnabled
        }
    }
}
