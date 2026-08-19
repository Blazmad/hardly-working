import CoreGraphics
import Foundation

protocol Jiggling {
    /// `false` when nothing was posted, so a caller never credits a nudge that
    /// never happened.
    @discardableResult
    func jiggle() -> Bool
}

/// Moves the cursor by one pixel and puts it straight back. Imperceptible, and
/// never emits a click.
struct MouseJiggler: Jiggling {
    @discardableResult
    func jiggle() -> Bool {
        guard let origin = currentCursorPosition() else {
            NSLog("Hardly Working: cursor position unreadable, no nudge posted")
            return false
        }
        move(to: CGPoint(x: origin.x + 1, y: origin.y))
        move(to: origin)
        return true
    }

    private func currentCursorPosition() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private func move(to point: CGPoint) {
        CGEvent(mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}
