import SwiftUI

@main
struct HardlyWorkingApp: App {
    var body: some Scene {
        MenuBarExtra("Hardly Working", systemImage: "cup.and.saucer.fill") {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
