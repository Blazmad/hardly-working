import SwiftUI

struct MenuView: View {
    @ObservedObject var controller: PresenceController
    @ObservedObject var settings: Settings

    let permission: PermissionChecking
    let loginItem: LoginItemManaging

    @State private var launchAtLogin = false

    var body: some View {
        alertBanner

        Toggle("Active", isOn: $settings.isEnabled)

        Divider()

        thresholdPicker
        Toggle("Launch at login", isOn: $launchAtLogin)

        Divider()

        quitButton
            .onAppear(perform: adoptCurrentSystemState)
            .onChange(of: settings.isEnabled) { _, _ in controller.refresh() }
            .onChange(of: settings.idleThresholdSeconds) { _, _ in controller.refresh() }
            .onChange(of: launchAtLogin) { _, isOn in updateLaunchAtLogin(to: isOn) }
    }
}

private extension MenuView {
    @ViewBuilder
    var alertBanner: some View {
        switch controller.state {
        case .needsPermission:
            Text("Accessibility permission required")
            Button("Open Accessibility Settings…", action: requestPermission)
            Divider()
        case .ineffective:
            Text("Mouse nudge had no effect — check Accessibility permission")
            Button("Open Accessibility Settings…", action: permission.openSettings)
            Divider()
        case .active, .paused:
            EmptyView()
        }
    }

    var thresholdPicker: some View {
        Picker("Idle threshold", selection: $settings.idleThresholdSeconds) {
            ForEach(Settings.availableThresholds, id: \.self) { seconds in
                Text(thresholdLabel(forSeconds: seconds)).tag(seconds)
            }
        }
    }

    var quitButton: some View {
        Button("Quit Hardly Working") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    func thresholdLabel(forSeconds seconds: Int) -> String {
        "\(seconds / 60) min"
    }

    func requestPermission() {
        permission.requestAccess()
        permission.openSettings()
    }

    func adoptCurrentSystemState() {
        launchAtLogin = loginItem.isEnabled
        controller.refresh()
    }

    /// Reads the flag back from the system: when registration fails, the checkbox
    /// has to fall back instead of claiming a state the system does not hold.
    func updateLaunchAtLogin(to isOn: Bool) {
        loginItem.setEnabled(isOn)
        launchAtLogin = loginItem.isEnabled
    }
}
