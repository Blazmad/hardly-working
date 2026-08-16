import CoreGraphics

protocol Jiggling {
    func jiggle()
}

/// Moves the cursor by one pixel and puts it straight back. Imperceptible, and
/// never emits a click.
struct MouseJiggler: Jiggling {
    func jiggle() {
        guard let origin = currentCursorPosition() else { return }
        move(to: CGPoint(x: origin.x + 1, y: origin.y))
        move(to: origin)
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
