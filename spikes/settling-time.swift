#!/usr/bin/env swift
import CoreGraphics
import Foundation

// Mesure : après avoir posté un événement souris synthétique, au bout de combien
// de temps le compteur d'inactivité système reflète-t-il réellement le mouvement ?
// Le code de production relit IMMÉDIATEMENT (délai 0). Cette mesure dit si c'est fiable.

func idle() -> TimeInterval {
    guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
    return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
}

func jiggle() {
    let origin = CGEvent(source: nil)?.location ?? .zero
    for p in [CGPoint(x: origin.x + 1, y: origin.y), origin] {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}

let delays: [TimeInterval] = [0, 0.001, 0.005, 0.020, 0.100, 0.500]
var successes = [TimeInterval: Int]()
let rounds = 12

print("Mesure du délai de propagation après un mouvement synthétique")
print("\(rounds) tours par délai. Ne touchez ni souris ni clavier.\n")
print("délai      | avant  | après  | compteur retombé ?")
print("-----------|--------|--------|-------------------")

for delay in delays {
    var ok = 0
    for _ in 1...rounds {
        // Laisser un peu d'inactivité s'accumuler pour que la chute soit mesurable.
        Thread.sleep(forTimeInterval: 0.4)
        let before = idle()
        jiggle()
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        let after = idle()
        // Le compteur est considéré « retombé » s'il est nettement inférieur à avant.
        if after < before - 0.1 { ok += 1 }
    }
    successes[delay] = ok
    let label = delay == 0 ? "immédiat " : String(format: "%6.0f ms", delay * 1000)
    print(String(format: "%@ | %2d/%2d tours réussis  %@", label, ok, rounds,
                 ok == rounds ? "✅ fiable" : (ok == 0 ? "❌ jamais" : "⚠️  INTERMITTENT")))
}

print("")
let immediate = successes[0] ?? 0
if immediate == rounds {
    print("VERDICT : la lecture immédiate est fiable (\(immediate)/\(rounds)).")
    print("          Le code de production tel quel ne produira pas de fausses alertes.")
} else {
    print("VERDICT : la lecture immédiate N'EST PAS fiable (\(immediate)/\(rounds)).")
    print("          Le code de production produirait de fausses alertes → hystérésis requise.")
}
