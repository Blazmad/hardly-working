import Foundation

/// La seule règle métier du produit, isolée pour être testable sans le système.
enum JiggleDecision {
    /// Faut-il provoquer un mouvement de souris maintenant ?
    static func shouldJiggle(idleSeconds: TimeInterval, thresholdSeconds: Int) -> Bool {
        idleSeconds >= TimeInterval(thresholdSeconds)
    }
}
