#!/usr/bin/env swift
import CoreGraphics
import Foundation

// Measurement: after posting a synthetic mouse event, how long does the system
// idle counter take to actually reflect the movement? The production code reads
// it back IMMEDIATELY (zero delay). This measurement says whether that is safe.

func idle() -> TimeInterval {
    guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
    return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
}

func jiggle() {
    let origin = CGEvent(source: nil)?.location ?? .zero
    for point in [CGPoint(x: origin.x + 1, y: origin.y), origin] {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}

let delays: [TimeInterval] = [0, 0.001, 0.005, 0.020, 0.100, 0.500]
var successes = [TimeInterval: Int]()
let rounds = 12

print("Measuring the propagation delay after a synthetic movement")
print("\(rounds) rounds per delay. Do not touch the mouse or keyboard.\n")
print("delay      | rounds where the counter dropped")
print("-----------|----------------------------------")

for delay in delays {
    var succeeded = 0
    for _ in 1...rounds {
        // Let some idle time build up so the drop is measurable.
        Thread.sleep(forTimeInterval: 0.4)
        let before = idle()
        jiggle()
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        let after = idle()
        // The counter counts as "dropped" when it is clearly below the reading
        // taken before the movement.
        if after < before - 0.1 { succeeded += 1 }
    }
    successes[delay] = succeeded
    let label = delay == 0 ? "immediate" : String(format: "%6.0f ms", delay * 1000)
    print(String(format: "%@ | %2d/%2d rounds  %@", label, succeeded, rounds,
                 succeeded == rounds ? "reliable" : (succeeded == 0 ? "never" : "INTERMITTENT")))
}

print("")
let immediate = successes[0] ?? 0
if immediate == rounds {
    print("VERDICT: reading back immediately is reliable (\(immediate)/\(rounds)).")
    print("         The production code as written will not raise false alarms.")
} else {
    print("VERDICT: reading back immediately is NOT reliable (\(immediate)/\(rounds)).")
    print("         The production code would raise false alarms - hysteresis required.")
}
