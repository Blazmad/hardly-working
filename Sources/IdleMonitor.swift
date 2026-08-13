import CoreGraphics
import Foundation

/// Fournit le temps écoulé depuis la dernière activité clavier ou souris.
protocol IdleMonitoring {
    func idleSeconds() -> TimeInterval
}

/// Lit le compteur d'inactivité réel de macOS — le même que celui consulté
/// par Teams, Slack et Discord pour décider d'afficher « away ».
struct SystemIdleMonitor: IdleMonitoring {
    func idleSeconds() -> TimeInterval {
        // ~0 correspond à kCGAnyInputEventType : n'importe quel événement d'entrée.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }
}
