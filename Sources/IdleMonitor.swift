import CoreGraphics
import Foundation

protocol IdleMonitoring {
    func idleSeconds() -> TimeInterval
}

/// Reads the real macOS idle counter, the one Teams, Slack and Discord consult
/// to decide whether to show you as away.
struct SystemIdleMonitor: IdleMonitoring {
    private static let anyInputEvent = CGEventType(rawValue: ~0)

    func idleSeconds() -> TimeInterval {
        guard let anyInputEvent = Self.anyInputEvent else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInputEvent)
    }
}
