import CoreGraphics

/// Provoque une activité souris minimale, suffisante pour réinitialiser
/// le compteur d'inactivité du système.
protocol Jiggling {
    func jiggle()
}

/// Déplace le curseur d'un pixel puis le ramène à sa position exacte.
/// Imperceptible à l'œil, et n'émet jamais de clic.
struct MouseJiggler: Jiggling {
    func jiggle() {
        guard let origin = CGEvent(source: nil)?.location else { return }
        move(to: CGPoint(x: origin.x + 1, y: origin.y))
        move(to: origin)
    }

    private func move(to point: CGPoint) {
        CGEvent(mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}
