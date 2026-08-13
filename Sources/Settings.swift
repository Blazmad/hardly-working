import Foundation

/// Réglages persistés entre les lancements.
final class Settings: ObservableObject {
    private enum Key {
        static let isEnabled = "isEnabled"
        static let idleThreshold = "idleThresholdSeconds"
    }

    /// Seuils proposés dans le menu, en secondes : 2, 3, 4, 5 et 10 minutes.
    static let availableThresholds: [Int] = [120, 180, 240, 300, 600]

    private let defaults: UserDefaults

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    @Published var idleThresholdSeconds: Int {
        didSet { defaults.set(idleThresholdSeconds, forKey: Key.idleThreshold) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.idleThreshold: 240,
        ])
        self.isEnabled = defaults.bool(forKey: Key.isEnabled)
        self.idleThresholdSeconds = defaults.integer(forKey: Key.idleThreshold)
    }
}
