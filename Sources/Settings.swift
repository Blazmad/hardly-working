import Foundation

final class Settings: ObservableObject {
    private enum Key {
        static let isEnabled = "isEnabled"
        static let idleThreshold = "idleThresholdSeconds"
    }

    private static let secondsPerMinute = 60

    static let availableThresholds = [2, 3, 4, 5, 10].map { $0 * Settings.secondsPerMinute }

    private static let defaultThresholdSeconds = 4 * secondsPerMinute

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
            Key.idleThreshold: Self.defaultThresholdSeconds,
        ])
        self.isEnabled = defaults.bool(forKey: Key.isEnabled)
        let stored = defaults.integer(forKey: Key.idleThreshold)
        /// The plist is writable by any same-user process (`defaults write`);
        /// only values from `availableThresholds` may reach the timer.
        self.idleThresholdSeconds = Self.availableThresholds.contains(stored)
            ? stored
            : Self.defaultThresholdSeconds
    }
}
