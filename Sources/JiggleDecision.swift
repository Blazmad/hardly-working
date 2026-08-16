import Foundation

enum JiggleDecision {
    static func shouldJiggle(idleSeconds: TimeInterval, thresholdSeconds: Int) -> Bool {
        idleSeconds >= TimeInterval(thresholdSeconds)
    }
}
